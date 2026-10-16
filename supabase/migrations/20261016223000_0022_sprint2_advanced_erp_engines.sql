-- Sprint 2: manufacturing valuation, FX realization primitives, and cash-flow forecast RPC.
-- Additive only. All operations are transactional; workflows remain opt-in until acceptance.

create table public.manufacturing_work_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  output_product_id uuid not null,
  planned_quantity numeric(14,3) not null check (planned_quantity > 0),
  completed_quantity numeric(14,3),
  status text not null default 'draft' check (status in ('draft','in_progress','completed','cancelled')),
  started_at timestamptz,
  completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,location_id) references public.locations(organization_id,id) on delete restrict,
  foreign key (organization_id,output_product_id) references public.products(organization_id,id) on delete restrict,
  check ((status='completed' and completed_at is not null and completed_quantity>0) or status<>'completed')
);
create index manufacturing_work_orders_org_status_idx on public.manufacturing_work_orders(organization_id,status,created_at desc);

create table public.manufacturing_work_order_components (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  work_order_id uuid not null,
  component_product_id uuid not null,
  quantity_per_output numeric(14,6) not null check (quantity_per_output > 0),
  scrap_rate numeric(7,4) not null default 0 check (scrap_rate between 0 and 100),
  created_at timestamptz not null default now(),
  unique (organization_id,work_order_id,component_product_id),
  foreign key (organization_id,work_order_id) references public.manufacturing_work_orders(organization_id,id) on delete restrict,
  foreign key (organization_id,component_product_id) references public.products(organization_id,id) on delete restrict
);
alter table public.manufacturing_work_orders enable row level security;
alter table public.manufacturing_work_order_components enable row level security;
create policy "Members read manufacturing work orders" on public.manufacturing_work_orders
  for select to authenticated using (public.is_organization_member(organization_id));
create policy "Members read manufacturing components" on public.manufacturing_work_order_components
  for select to authenticated using (public.is_organization_member(organization_id));
revoke insert,update,delete on public.manufacturing_work_orders,public.manufacturing_work_order_components from anon,authenticated;

alter table public.inventory_movements drop constraint if exists inventory_movements_movement_type_check;
alter table public.inventory_movements add constraint inventory_movements_movement_type_check
  check (movement_type in ('opening','receiving','adjustment','sale','return','reversal','manufacturing_component','manufacturing_output'));
alter table public.inventory_valuation_movements drop constraint if exists inventory_valuation_movements_movement_type_check;
alter table public.inventory_valuation_movements add constraint inventory_valuation_movements_movement_type_check
  check (movement_type in ('opening','receiving','sale','return','adjustment','writeoff','reversal','transfer_in','transfer_out','manufacturing_component','manufacturing_output'));

create or replace function public.apply_completed_manufacturing_work_order()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  comp record;
  qty_needed numeric(14,3);
  before_qty numeric(14,3);
  after_qty numeric(14,3);
  before_value numeric(16,2);
  after_value numeric(16,2);
  avg_cost numeric(16,6);
  component_cost numeric(16,2) := 0;
  consumed_cost numeric(16,2);
  output_value numeric(16,2);
  output_qty numeric(14,3);
  output_before numeric(14,3);
  output_after numeric(14,3);
  output_value_before numeric(16,2);
  output_value_after numeric(16,2);
  output_avg numeric(16,6);
  move_id uuid;
begin
  if not (OLD.status='in_progress' and NEW.status='completed') then return NEW; end if;
  if NEW.completed_quantity is null or NEW.completed_quantity<=0 then
    raise exception 'Completed quantity must be positive.' using errcode='23514';
  end if;
  if not exists(select 1 from public.accounting_settings where organization_id=NEW.organization_id) then
    raise exception 'Accounting settings are not initialized.' using errcode='23514';
  end if;
  if not exists(select 1 from public.manufacturing_work_order_components c where c.organization_id=NEW.organization_id and c.work_order_id=NEW.id) then
    raise exception 'Work order requires at least one component.' using errcode='23514';
  end if;

  -- Deterministic component order avoids deadlocks when work orders share components.
  for comp in
    select c.component_product_id, c.quantity_per_output, c.scrap_rate
    from public.manufacturing_work_order_components c
    where c.organization_id=NEW.organization_id and c.work_order_id=NEW.id
    order by c.component_product_id
  loop
    qty_needed := round(NEW.completed_quantity * comp.quantity_per_output * (1 + comp.scrap_rate / 100.0), 3);
    insert into public.inventory_balances(organization_id,location_id,product_id,quantity,reorder_level)
      values(NEW.organization_id,NEW.location_id,comp.component_product_id,0,0)
      on conflict(location_id,product_id) do nothing;
    insert into public.inventory_valuation_balances(organization_id,location_id,product_id,quantity,carrying_value,average_unit_cost)
      values(NEW.organization_id,NEW.location_id,comp.component_product_id,0,0,0)
      on conflict(location_id,product_id) do nothing;

    select quantity into before_qty from public.inventory_balances
      where organization_id=NEW.organization_id and location_id=NEW.location_id and product_id=comp.component_product_id for update;
    select quantity,carrying_value,average_unit_cost into output_qty,before_value,avg_cost
      from public.inventory_valuation_balances
      where organization_id=NEW.organization_id and location_id=NEW.location_id and product_id=comp.component_product_id for update;
    if before_qty < qty_needed or output_qty < qty_needed then
      raise exception 'Insufficient component stock for manufacturing work order.' using errcode='23514';
    end if;
    after_qty := before_qty - qty_needed;
    after_value := round(before_value - case when qty_needed=output_qty then before_value else qty_needed*avg_cost end,2);
    consumed_cost := round(before_value - after_value,2);
    if after_value<0 then raise exception 'Manufacturing component valuation cannot become negative.' using errcode='23514'; end if;
    update public.inventory_balances set quantity=after_qty,updated_at=now()
      where organization_id=NEW.organization_id and location_id=NEW.location_id and product_id=comp.component_product_id;
    update public.inventory_valuation_balances set quantity=after_qty,carrying_value=after_value,
      average_unit_cost=case when after_qty=0 then 0 else round(after_value/after_qty,6) end,updated_at=now()
      where organization_id=NEW.organization_id and location_id=NEW.location_id and product_id=comp.component_product_id;
    insert into public.inventory_movements(organization_id,location_id,product_id,movement_type,quantity_delta,quantity_before,quantity_after,reference_type,reference_id,note,created_by)
      values(NEW.organization_id,NEW.location_id,comp.component_product_id,'manufacturing_component',-qty_needed,before_qty,after_qty,'manufacturing_work_order',NEW.id,'Component consumed by manufacturing',NEW.created_by)
      returning id into move_id;
    insert into public.inventory_valuation_movements(organization_id,location_id,product_id,inventory_movement_id,movement_type,source_type,source_id,quantity_delta,unit_cost,value_delta,quantity_before,quantity_after,value_before,value_after,average_cost_after,note,created_by)
      values(NEW.organization_id,NEW.location_id,comp.component_product_id,move_id,'manufacturing_component','manufacturing_work_order',NEW.id,-qty_needed,avg_cost,-consumed_cost,output_qty,output_qty-qty_needed,before_value,after_value,case when after_qty=0 then 0 else round(after_value/after_qty,6) end,'Manufacturing component consumption',NEW.created_by);
    component_cost := component_cost + consumed_cost;
  end loop;

  output_value := round(component_cost,2);
  output_qty := NEW.completed_quantity;
  insert into public.inventory_balances(organization_id,location_id,product_id,quantity,reorder_level)
    values(NEW.organization_id,NEW.location_id,NEW.output_product_id,0,0)
    on conflict(location_id,product_id) do nothing;
  insert into public.inventory_valuation_balances(organization_id,location_id,product_id,quantity,carrying_value,average_unit_cost)
    values(NEW.organization_id,NEW.location_id,NEW.output_product_id,0,0,0)
    on conflict(location_id,product_id) do nothing;
  select quantity into output_before from public.inventory_balances
    where organization_id=NEW.organization_id and location_id=NEW.location_id and product_id=NEW.output_product_id for update;
  select quantity,carrying_value into output_qty,output_value_before from public.inventory_valuation_balances
    where organization_id=NEW.organization_id and location_id=NEW.location_id and product_id=NEW.output_product_id for update;
  output_after := output_before + NEW.completed_quantity;
  output_value_after := round(output_value_before + output_value,2);
  output_avg := case when output_after>0 then round(output_value_after/output_after,6) else 0 end;
  update public.inventory_balances set quantity=output_after,updated_at=now()
    where organization_id=NEW.organization_id and location_id=NEW.location_id and product_id=NEW.output_product_id;
  update public.inventory_valuation_balances set quantity=output_after,carrying_value=output_value_after,average_unit_cost=output_avg,updated_at=now()
    where organization_id=NEW.organization_id and location_id=NEW.location_id and product_id=NEW.output_product_id;
  insert into public.inventory_movements(organization_id,location_id,product_id,movement_type,quantity_delta,quantity_before,quantity_after,reference_type,reference_id,note,created_by)
    values(NEW.organization_id,NEW.location_id,NEW.output_product_id,'manufacturing_output',NEW.completed_quantity,output_before,output_after,'manufacturing_work_order',NEW.id,'Finished goods produced',NEW.created_by)
    returning id into move_id;
  insert into public.inventory_valuation_movements(organization_id,location_id,product_id,inventory_movement_id,movement_type,source_type,source_id,quantity_delta,unit_cost,value_delta,quantity_before,quantity_after,value_before,value_after,average_cost_after,note,created_by)
    values(NEW.organization_id,NEW.location_id,NEW.output_product_id,move_id,'manufacturing_output','manufacturing_work_order',NEW.id,NEW.completed_quantity,output_avg,output_value,output_before,output_after,output_value_before,output_value_after,output_avg,'Finished goods valued at consumed component cost',NEW.created_by);
  return NEW;
end;
$$;
revoke all on function public.apply_completed_manufacturing_work_order() from public,anon,authenticated;
create trigger manufacturing_work_order_completion_reflection
  before update of status on public.manufacturing_work_orders
  for each row when (OLD.status='in_progress' and NEW.status='completed')
  execute function public.apply_completed_manufacturing_work_order();

-- Transaction currency is retained beside functional KES values. Rates are KES per 1 unit of invoice currency.
alter table public.supplier_bills
  add column if not exists exchange_rate_to_kes numeric(18,8) not null default 1 check (exchange_rate_to_kes>0),
  add column if not exists functional_total_kes numeric(18,2) generated always as (round((subtotal+input_tax)*exchange_rate_to_kes,2)) stored;
alter table public.supplier_bill_payments
  add column if not exists settlement_exchange_rate_to_kes numeric(18,8) not null default 1 check (settlement_exchange_rate_to_kes>0);
alter table public.sales_documents
  add column if not exists exchange_rate_to_kes numeric(18,8) not null default 1 check (exchange_rate_to_kes>0),
  add column if not exists functional_total_kes numeric(18,2) generated always as (round(grand_total*exchange_rate_to_kes,2)) stored;
alter table public.document_payments
  add column if not exists settlement_exchange_rate_to_kes numeric(18,8) not null default 1 check (settlement_exchange_rate_to_kes>0),
  add column if not exists functional_amount_kes numeric(18,2) generated always as (round(amount*settlement_exchange_rate_to_kes,2)) stored;

insert into public.chart_of_accounts(organization_id,code,name,account_type,normal_balance,is_control,control_type,system_key)
select o.id,'7901','Realized FX loss','expense','debit',false,null,'realized_fx_loss' from public.organizations o
on conflict (organization_id,system_key) do nothing;
insert into public.chart_of_accounts(organization_id,code,name,account_type,normal_balance,is_control,control_type,system_key)
select o.id,'4901','Realized FX gain','revenue','credit',false,null,'realized_fx_gain' from public.organizations o
on conflict (organization_id,system_key) do nothing;

create or replace function public.post_realized_fx_adjustment(
  p_organization_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_accounting_date date,
  p_description text,
  p_gain_loss_kes numeric,
  p_control_account_key text
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  control_id uuid;
  fx_id uuid;
  lines jsonb;
begin
  if p_gain_loss_kes is null or round(p_gain_loss_kes,2)=0 then return null; end if;
  select id into control_id from public.chart_of_accounts
    where organization_id=p_organization_id and system_key=p_control_account_key and is_active;
  select id into fx_id from public.chart_of_accounts
    where organization_id=p_organization_id and system_key=case when p_gain_loss_kes>0 then 'realized_fx_gain' else 'realized_fx_loss' end and is_active;
  if control_id is null or fx_id is null then raise exception 'FX control or gain/loss account is missing.' using errcode='23514'; end if;
  -- Positive amount is a gain: debit the receivable/payable control and credit FX gain.
  lines := case when p_gain_loss_kes>0 then jsonb_build_array(
    jsonb_build_object('account_id',control_id,'debit',abs(round(p_gain_loss_kes,2)),'credit',0,'description','Realized foreign exchange control adjustment'),
    jsonb_build_object('account_id',fx_id,'debit',0,'credit',abs(round(p_gain_loss_kes,2)),'description','Realized FX gain'))
  else jsonb_build_array(
    jsonb_build_object('account_id',fx_id,'debit',abs(round(p_gain_loss_kes,2)),'credit',0,'description','Realized FX loss'),
    jsonb_build_object('account_id',control_id,'debit',0,'credit',abs(round(p_gain_loss_kes,2)),'description','Realized foreign exchange control adjustment')) end;
  return public.post_accounting_journal_internal(p_organization_id,p_accounting_date,p_description,p_source_type,p_source_id,'realized_fx',lines,null);
end;
$$;
revoke all on function public.post_realized_fx_adjustment(uuid,text,uuid,date,text,numeric,text) from public,anon,authenticated;

create or replace function public.realize_supplier_bill_payment_fx()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  bill public.supplier_bills%rowtype;
  paid_base numeric(18,2);
  book_base numeric(18,2);
  fx_difference numeric(18,2);
begin
  select * into bill from public.supplier_bills where organization_id=NEW.organization_id and id=NEW.bill_id for update;
  if not found or bill.currency_code='KES' then return NEW; end if;
  paid_base := round(NEW.amount*NEW.settlement_exchange_rate_to_kes,2);
  book_base := round(NEW.amount*bill.exchange_rate_to_kes,2);
  -- For payables, paying more KES than the booked liability realizes a loss.
  fx_difference := book_base-paid_base;
  perform public.post_realized_fx_adjustment(NEW.organization_id,'supplier_bill_payment',NEW.id,(NEW.paid_at at time zone 'Africa/Nairobi')::date,
    'Realized FX on supplier bill payment',fx_difference,'accounts_payable');
  return NEW;
end;
$$;
revoke all on function public.realize_supplier_bill_payment_fx() from public,anon,authenticated;
create trigger supplier_bill_payment_realized_fx after insert on public.supplier_bill_payments
for each row execute function public.realize_supplier_bill_payment_fx();

create or replace function public.realize_customer_payment_fx()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  doc public.sales_documents%rowtype;
  book_base numeric(18,2);
  received_base numeric(18,2);
  fx_difference numeric(18,2);
begin
  if NEW.status<>'succeeded' then return NEW; end if;
  select * into doc from public.sales_documents where organization_id=NEW.organization_id and id=NEW.document_id for update;
  if not found or doc.currency_code='KES' then return NEW; end if;
  book_base := round(NEW.amount*doc.exchange_rate_to_kes,2);
  received_base := round(NEW.amount*NEW.settlement_exchange_rate_to_kes,2);
  -- For receivables, receiving more KES than the booked receivable realizes a gain.
  fx_difference := received_base-book_base;
  perform public.post_realized_fx_adjustment(NEW.organization_id,'document_payment',NEW.id,(coalesce(NEW.confirmed_at,now()) at time zone 'Africa/Nairobi')::date,
    'Realized FX on customer receipt',fx_difference,'accounts_receivable');
  return NEW;
end;
$$;
revoke all on function public.realize_customer_payment_fx() from public,anon,authenticated;
create trigger document_payment_realized_fx after insert or update of status on public.document_payments
for each row execute function public.realize_customer_payment_fx();

-- Member-scoped daily historical cash/bank flows plus a 30-day deterministic forecast.
create or replace function public.get_cash_flow_forecast(p_organization_id uuid,p_history_days integer default 90)
returns table(
  flow_date date,
  actual_inflow_kes numeric,
  actual_outflow_kes numeric,
  projected_closing_kes numeric,
  lower_bound_kes numeric,
  upper_bound_kes numeric,
  is_forecast boolean
)
language plpgsql security definer set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  history_days integer := greatest(30,least(coalesce(p_history_days,90),365));
  opening_balance numeric(18,2);
  daily_mean numeric(18,2);
  daily_sigma numeric(18,2);
begin
  if caller is null or not exists(
    select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=caller
  ) then raise exception 'Workspace access denied.' using errcode='42501'; end if;

  select coalesce(sum(case when a.normal_balance='debit' then l.debit-l.credit else l.credit-l.debit end),0)
    into opening_balance
  from public.journal_lines l
  join public.journal_entries j on j.organization_id=l.organization_id and j.id=l.journal_entry_id and j.status='posted'
  join public.chart_of_accounts a on a.organization_id=l.organization_id and a.id=l.account_id
  where l.organization_id=p_organization_id and a.system_key in ('cash','bank')
    and j.accounting_date<=current_date;

  with daily as (
    select j.accounting_date,
      sum(case when (a.normal_balance='debit' and l.debit>l.credit) or (a.normal_balance='credit' and l.credit>l.debit)
        then abs(l.debit-l.credit) else 0 end) as inflow,
      sum(case when (a.normal_balance='debit' and l.credit>l.debit) or (a.normal_balance='credit' and l.debit>l.credit)
        then abs(l.debit-l.credit) else 0 end) as outflow
    from public.journal_lines l
    join public.journal_entries j on j.organization_id=l.organization_id and j.id=l.journal_entry_id and j.status='posted'
    join public.chart_of_accounts a on a.organization_id=l.organization_id and a.id=l.account_id
    where l.organization_id=p_organization_id and a.system_key in ('cash','bank')
      and j.accounting_date between current_date-history_days and current_date
    group by j.accounting_date
  )
  select coalesce(avg(inflow-outflow),0),coalesce(stddev_pop(inflow-outflow),0)
    into daily_mean,daily_sigma from daily;

  return query
  with dates as (
    select d::date as d from generate_series(current_date-history_days+1,current_date+30,interval '1 day') d
  ),
  flows as (
    select j.accounting_date as d,
      sum(case when (a.normal_balance='debit' and l.debit>l.credit) or (a.normal_balance='credit' and l.credit>l.debit)
        then abs(l.debit-l.credit) else 0 end)::numeric(18,2) as inflow,
      sum(case when (a.normal_balance='debit' and l.credit>l.debit) or (a.normal_balance='credit' and l.debit>l.credit)
        then abs(l.debit-l.credit) else 0 end)::numeric(18,2) as outflow
    from public.journal_lines l
    join public.journal_entries j on j.organization_id=l.organization_id and j.id=l.journal_entry_id and j.status='posted'
    join public.chart_of_accounts a on a.organization_id=l.organization_id and a.id=l.account_id
    where l.organization_id=p_organization_id and a.system_key in ('cash','bank')
      and j.accounting_date between current_date-history_days+1 and current_date
    group by j.accounting_date
  ),
  series as (
    select d.d,coalesce(f.inflow,0) inflow,coalesce(f.outflow,0) outflow,
      d.d>current_date as forecast_day
    from dates d left join flows f on f.d=d.d
  ),
  projected as (
    select s.*,
      opening_balance + sum(case when s.d<=current_date then s.inflow-s.outflow else daily_mean end)
        over(order by s.d rows between unbounded preceding and current row) as balance,
      sqrt(greatest((s.d-current_date)::numeric,0))*daily_sigma*1.96 as margin
    from series s
  )
  select p.d,
    case when p.d<=current_date then p.inflow else 0 end,
    case when p.d<=current_date then p.outflow else 0 end,
    round(p.balance,2),round(p.balance-p.margin,2),round(p.balance+p.margin,2),p.forecast_day
  from projected p order by p.d;
end;
$$;
revoke all on function public.get_cash_flow_forecast(uuid,integer) from public,anon;
grant execute on function public.get_cash_flow_forecast(uuid,integer) to authenticated;
comment on function public.get_cash_flow_forecast(uuid,integer) is
  'Returns posted cash/bank history and a 30-day mean/stdev projection. Projection is statistical, not a commitment schedule.';
