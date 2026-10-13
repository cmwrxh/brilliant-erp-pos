-- SafariPOS perpetual inventory valuation and verified sale posting.
-- Additive foundation. Validate with the accounting CPA before live financial reliance.
create table public.inventory_valuation_balances (
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  product_id uuid not null,
  quantity numeric(14,3) not null default 0 check (quantity >= 0),
  carrying_value numeric(16,2) not null default 0 check (carrying_value >= 0),
  average_unit_cost numeric(16,6) not null default 0 check (average_unit_cost >= 0),
  updated_at timestamptz not null default now(),
  primary key(location_id,product_id),
  foreign key (organization_id,location_id) references public.locations(organization_id,id) on delete restrict,
  foreign key (organization_id,product_id) references public.products(organization_id,id) on delete restrict,
  check ((quantity=0 and carrying_value=0) or quantity>0)
);
create table public.inventory_valuation_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  product_id uuid not null,
  inventory_movement_id uuid unique references public.inventory_movements(id) on delete restrict,
  movement_type text not null check (movement_type in ('opening','receiving','sale','return','adjustment','writeoff','reversal','transfer_in','transfer_out')),
  source_type text,
  source_id uuid,
  quantity_delta numeric(14,3) not null check (quantity_delta<>0),
  unit_cost numeric(16,6) not null default 0 check (unit_cost>=0),
  value_delta numeric(16,2) not null,
  quantity_before numeric(14,3) not null check (quantity_before>=0),
  quantity_after numeric(14,3) not null check (quantity_after>=0),
  value_before numeric(16,2) not null check (value_before>=0),
  value_after numeric(16,2) not null check (value_after>=0),
  average_cost_after numeric(16,6) not null check (average_cost_after>=0),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (organization_id,location_id) references public.locations(organization_id,id) on delete restrict,
  foreign key (organization_id,product_id) references public.products(organization_id,id) on delete restrict,
  check (quantity_after=quantity_before+quantity_delta),
  check (value_after=round(value_before+value_delta,2))
);
create index inventory_valuation_movements_org_time_idx on public.inventory_valuation_movements(organization_id,created_at desc);
create index inventory_valuation_movements_product_idx on public.inventory_valuation_movements(organization_id,location_id,product_id,created_at desc);
alter table public.inventory_valuation_balances enable row level security;
alter table public.inventory_valuation_movements enable row level security;
create policy "Members read inventory valuation" on public.inventory_valuation_balances for select to authenticated using (public.is_organization_member(organization_id));
create policy "Members read inventory valuation movements" on public.inventory_valuation_movements for select to authenticated using (public.is_organization_member(organization_id));
revoke all on public.inventory_valuation_balances,public.inventory_valuation_movements from anon;
revoke insert,update,delete on public.inventory_valuation_balances,public.inventory_valuation_movements from authenticated;

-- Backfill existing on-hand quantities at the legacy product cost; review as a cutover schedule.
insert into public.inventory_valuation_balances(organization_id,location_id,product_id,quantity,carrying_value,average_unit_cost)
select ib.organization_id,ib.location_id,ib.product_id,ib.quantity,
       round(ib.quantity*p.cost_price,2),
       case when ib.quantity>0 then p.cost_price else 0 end
from public.inventory_balances ib join public.products p
  on p.organization_id=ib.organization_id and p.id=ib.product_id
on conflict(location_id,product_id) do nothing;

-- Internal account-template seeder. Only trusted functions/triggers can execute it.
create or replace function public.seed_safaripos_accounting_template(p_organization_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.accounting_settings(organization_id) values(p_organization_id) on conflict do nothing;
  insert into public.chart_of_accounts(organization_id,code,name,account_type,normal_balance,is_control,control_type,system_key)
  values
  (p_organization_id,'1000','Cash on hand','asset','debit',true,'cash','cash'),
  (p_organization_id,'1010','Bank current account','asset','debit',true,'bank','bank'),
  (p_organization_id,'1020','M-PESA clearing','asset','debit',true,'mpesa_clearing','mpesa_clearing'),
  (p_organization_id,'1030','Payment provider clearing','asset','debit',true,'payment_clearing','payment_clearing'),
  (p_organization_id,'1100','Accounts receivable control','asset','debit',true,'accounts_receivable','accounts_receivable'),
  (p_organization_id,'1110','Allowance for doubtful debts','asset','credit',false,null,'doubtful_debts'),
  (p_organization_id,'1200','Inventory control','asset','debit',true,'inventory','inventory'),
  (p_organization_id,'1210','Input VAT recoverable','asset','debit',true,'vat_input','vat_input'),
  (p_organization_id,'1300','Prepayments','asset','debit',false,null,'prepayments'),
  (p_organization_id,'1500','Property, plant and equipment','asset','debit',false,null,'fixed_assets'),
  (p_organization_id,'1590','Accumulated depreciation','asset','credit',false,null,'accumulated_depreciation'),
  (p_organization_id,'2000','Accounts payable control','liability','credit',true,'accounts_payable','accounts_payable'),
  (p_organization_id,'2090','Goods received not invoiced','liability','credit',false,null,'goods_received_not_invoiced'),
  (p_organization_id,'2100','Output VAT payable','liability','credit',true,'vat_output','vat_output'),
  (p_organization_id,'2110','VAT control / settlement','liability','credit',false,null,'vat_settlement'),
  (p_organization_id,'2200','Accrued expenses','liability','credit',false,null,'accrued_expenses'),
  (p_organization_id,'2210','Salaries and statutory deductions payable','liability','credit',false,null,'salary_payable'),
  (p_organization_id,'2300','Customer deposits / deferred revenue','liability','credit',false,null,'customer_deposits'),
  (p_organization_id,'2400','Loans payable','liability','credit',false,null,'loans_payable'),
  (p_organization_id,'3000','Owner capital / share capital','equity','credit',false,null,'owner_capital'),
  (p_organization_id,'3100','Additional owner contributions','equity','credit',false,null,'owner_contributions'),
  (p_organization_id,'3200','Owner drawings','equity','debit',false,null,'owner_drawings'),
  (p_organization_id,'3300','Retained earnings','equity','credit',false,null,'retained_earnings'),
  (p_organization_id,'3900','Current-year earnings','equity','credit',false,null,'current_year_earnings'),
  (p_organization_id,'4000','Retail sales revenue','revenue','credit',false,null,'retail_sales'),
  (p_organization_id,'4010','Wholesale sales revenue','revenue','credit',false,null,'wholesale_sales'),
  (p_organization_id,'4020','Sales returns and allowances','revenue','debit',false,null,'sales_returns'),
  (p_organization_id,'4030','Sales discounts','revenue','debit',false,null,'sales_discounts'),
  (p_organization_id,'4100','Other operating income','revenue','credit',false,null,'other_income'),
  (p_organization_id,'5000','Cost of goods sold','expense','debit',false,null,'cogs'),
  (p_organization_id,'5010','Inventory expiry / write-off','expense','debit',false,null,'inventory_writeoff'),
  (p_organization_id,'5020','Stocktake shrinkage / adjustment','expense','debit',false,null,'stocktake_adjustment'),
  (p_organization_id,'6000','Rent expense','expense','debit',false,null,'rent_expense'),
  (p_organization_id,'6010','Salaries and wages','expense','debit',false,null,'salary_expense'),
  (p_organization_id,'6020','Employer payroll costs','expense','debit',false,null,'employer_payroll'),
  (p_organization_id,'6100','Utilities and communications','expense','debit',false,null,'utilities'),
  (p_organization_id,'6110','Transport and delivery','expense','debit',false,null,'transport'),
  (p_organization_id,'6120','Payment processing / M-PESA fees','expense','debit',false,null,'payment_fees'),
  (p_organization_id,'6130','Repairs and maintenance','expense','debit',false,null,'repairs'),
  (p_organization_id,'6200','Depreciation expense','expense','debit',false,null,'depreciation_expense'),
  (p_organization_id,'6300','Bad debt expense','expense','debit',false,null,'bad_debt'),
  (p_organization_id,'6400','Cash over / short','expense','debit',false,null,'cash_over_short'),
  (p_organization_id,'6500','Income tax expense','expense','debit',false,null,'income_tax'),
  (p_organization_id,'7000','Gain / loss on asset disposal','expense','debit',false,null,'asset_disposal')
  on conflict (organization_id,code) do nothing;
end;
$$;
revoke all on function public.seed_safaripos_accounting_template(uuid) from public,anon,authenticated;

create or replace function public.seed_safaripos_accounting_on_organization()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.seed_safaripos_accounting_template(NEW.id);
  return NEW;
end;
$$;
revoke all on function public.seed_safaripos_accounting_on_organization() from public,anon,authenticated;
create trigger seed_accounting_on_new_organization after insert on public.organizations
for each row execute function public.seed_safaripos_accounting_on_organization();

do $$
declare org_row record;
begin
  for org_row in select id from public.organizations loop
    perform public.seed_safaripos_accounting_template(org_row.id);
  end loop;
end $$;

-- Private posting path for trusted transaction functions/triggers. Never grant it to API roles.
create or replace function public.post_accounting_journal_internal(
  p_organization_id uuid,
  p_accounting_date date,
  p_description text,
  p_source_type text,
  p_source_id uuid,
  p_posting_purpose text,
  p_lines jsonb,
  p_reverses_journal_id uuid default null
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  journal_id uuid;
  next_number bigint;
  line jsonb;
  line_no integer := 0;
  total_debit numeric(16,2);
  total_credit numeric(16,2);
  existing_status text;
begin
  if p_accounting_date is null or p_description is null or length(trim(p_description))<2 or p_source_type is null or p_source_id is null or p_posting_purpose is null then
    raise exception 'Date, description, source and posting purpose are required.' using errcode='22023';
  end if;
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<2 then raise exception 'At least two journal lines are required.' using errcode='22023'; end if;
  if not exists(select 1 from public.accounting_settings where organization_id=p_organization_id) then
    raise exception 'Initialize the business chart of accounts before posting.' using errcode='23514';
  end if;
  perform 1 from public.accounting_settings where organization_id=p_organization_id for update;
  if exists(select 1 from public.accounting_periods where organization_id=p_organization_id and p_accounting_date between starts_on and ends_on and status='closed') then
    raise exception 'Accounting period is closed.' using errcode='23514';
  end if;
  if exists(select 1 from public.accounting_periods where organization_id=p_organization_id and p_accounting_date between starts_on and ends_on) is false
     and exists(select 1 from public.accounting_periods where organization_id=p_organization_id) then
    raise exception 'Accounting date is outside an open accounting period.' using errcode='23514';
  end if;
  select id,status into journal_id,existing_status from public.journal_entries
    where organization_id=p_organization_id and source_type=p_source_type and source_id=p_source_id and posting_purpose=p_posting_purpose;
  if journal_id is not null then
    if existing_status in ('posted','reversed') then return journal_id; end if;
    raise exception 'An unfinished journal already exists for this source; investigate before retrying.' using errcode='23514';
  end if;
  select coalesce(max(journal_number),0)+1 into next_number from public.journal_entries where organization_id=p_organization_id;
  insert into public.journal_entries(organization_id,journal_number,accounting_date,description,source_type,source_id,posting_purpose,status,reversed_entry_id,created_by)
  values(p_organization_id,next_number,p_accounting_date,left(trim(p_description),500),p_source_type,p_source_id,p_posting_purpose,'draft',p_reverses_journal_id,caller)
  on conflict (organization_id,source_type,source_id,posting_purpose) do nothing returning id into journal_id;
  if journal_id is null then
    select id into journal_id from public.journal_entries where organization_id=p_organization_id and source_type=p_source_type and source_id=p_source_id and posting_purpose=p_posting_purpose;
    return journal_id;
  end if;
  for line in select value from jsonb_array_elements(p_lines) loop
    line_no := line_no + 1;
    if coalesce((line->>'debit')::numeric,0)<0 or coalesce((line->>'credit')::numeric,0)<0
      or not ((coalesce((line->>'debit')::numeric,0)>0 and coalesce((line->>'credit')::numeric,0)=0)
       or (coalesce((line->>'credit')::numeric,0)>0 and coalesce((line->>'debit')::numeric,0)=0)) then
      raise exception 'Each journal line must have a positive debit or a positive credit, never both.' using errcode='23514';
    end if;
    if not exists(select 1 from public.chart_of_accounts a where a.organization_id=p_organization_id and a.id=(line->>'account_id')::uuid and a.is_active) then
      raise exception 'Journal references an invalid or inactive account.' using errcode='23503';
    end if;
    insert into public.journal_lines(organization_id,journal_entry_id,line_number,account_id,description,debit,credit,source_reference)
    values(p_organization_id,journal_id,line_no,(line->>'account_id')::uuid,left(line->>'description',500),
      coalesce((line->>'debit')::numeric,0),coalesce((line->>'credit')::numeric,0),left(line->>'source_reference',200));
  end loop;
  select coalesce(sum(debit),0),coalesce(sum(credit),0) into total_debit,total_credit from public.journal_lines where organization_id=p_organization_id and journal_entry_id=journal_id;
  if total_debit<>total_credit then raise exception 'Unbalanced journal: debit total %, credit total %.',total_debit,total_credit using errcode='23514'; end if;
  update public.journal_entries set status='posted',posted_at=now(),posted_by=caller where id=journal_id and organization_id=p_organization_id;
  update public.accounting_settings set locked_at=coalesce(locked_at,now()),updated_at=now() where organization_id=p_organization_id;
  return journal_id;
end;
$$;
revoke all on function public.post_accounting_journal_internal(uuid,date,text,text,uuid,text,jsonb,uuid) from public,anon,authenticated,service_role;


create or replace function public.record_inventory_receipt_valued(
  p_organization_id uuid,
  p_location_id uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_unit_cost numeric,
  p_note text default null
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  caller_role public.business_role;
  before_qty numeric(14,3);
  after_qty numeric(14,3);
  before_value numeric(16,2);
  receipt_value numeric(16,2);
  after_value numeric(16,2);
  avg_cost numeric(16,6);
  inventory_move_id uuid;
  valuation_move_id uuid;
  inventory_account uuid;
  grni_account uuid;
begin
  if caller is null then raise exception 'Authentication required' using errcode='28000'; end if;
  select role into caller_role from public.organization_members where organization_id=p_organization_id and user_id=caller;
  if caller_role is null or caller_role not in ('owner','admin','manager','inventory') then raise exception 'Not authorized to receive stock.' using errcode='42501'; end if;
  if p_quantity is null or p_quantity<=0 or p_quantity>1000000 or p_unit_cost is null or p_unit_cost<0 or p_unit_cost>1000000000 then
    raise exception 'Enter a valid positive quantity and non-negative unit cost.' using errcode='22023';
  end if;
  if not exists(select 1 from public.locations where id=p_location_id and organization_id=p_organization_id and is_active)
     or not exists(select 1 from public.products where id=p_product_id and organization_id=p_organization_id and is_active) then
    raise exception 'Invalid or inactive location/product.' using errcode='23503';
  end if;
  insert into public.inventory_balances(organization_id,location_id,product_id,quantity,reorder_level)
  values(p_organization_id,p_location_id,p_product_id,0,0)
  on conflict(location_id,product_id) do nothing;
  insert into public.inventory_valuation_balances(organization_id,location_id,product_id,quantity,carrying_value,average_unit_cost)
  values(p_organization_id,p_location_id,p_product_id,0,0,0)
  on conflict(location_id,product_id) do nothing;
  select quantity into before_qty from public.inventory_balances where organization_id=p_organization_id and location_id=p_location_id and product_id=p_product_id for update;
  select carrying_value into before_value from public.inventory_valuation_balances where organization_id=p_organization_id and location_id=p_location_id and product_id=p_product_id for update;
  after_qty := before_qty+p_quantity;
  receipt_value := round(p_quantity*p_unit_cost,2);
  after_value := round(before_value+receipt_value,2);
  avg_cost := case when after_qty>0 then round(after_value/after_qty,6) else 0 end;
  update public.inventory_balances set quantity=after_qty,updated_at=now()
    where organization_id=p_organization_id and location_id=p_location_id and product_id=p_product_id;
  insert into public.inventory_movements(organization_id,location_id,product_id,movement_type,quantity_delta,quantity_before,quantity_after,reference_type,note,created_by)
  values(p_organization_id,p_location_id,p_product_id,'receiving',p_quantity,before_qty,after_qty,'inventory_receipt',left(p_note,500),caller)
  returning id into inventory_move_id;
  update public.inventory_valuation_balances set quantity=after_qty,carrying_value=after_value,average_unit_cost=avg_cost,updated_at=now()
    where organization_id=p_organization_id and location_id=p_location_id and product_id=p_product_id;
  insert into public.inventory_valuation_movements(organization_id,location_id,product_id,inventory_movement_id,movement_type,source_type,source_id,quantity_delta,unit_cost,value_delta,quantity_before,quantity_after,value_before,value_after,average_cost_after,note,created_by)
  values(p_organization_id,p_location_id,p_product_id,inventory_move_id,'receiving','inventory_receipt',inventory_move_id,p_quantity,p_unit_cost,receipt_value,before_qty,after_qty,before_value,after_value,avg_cost,left(p_note,500),caller)
  returning id into valuation_move_id;
  if receipt_value>0 then
    select id into inventory_account from public.chart_of_accounts where organization_id=p_organization_id and system_key='inventory' and is_active;
    select id into grni_account from public.chart_of_accounts where organization_id=p_organization_id and system_key='goods_received_not_invoiced' and is_active;
    if inventory_account is null or grni_account is null then raise exception 'Inventory/GRNI accounts are not configured.' using errcode='23514'; end if;
    perform public.post_accounting_journal_internal(p_organization_id,current_date,'Stock receipt: '||coalesce(left(p_note,350),'inventory receiving'),'inventory_receipt',valuation_move_id,'valuation',
      jsonb_build_array(
        jsonb_build_object('account_id',inventory_account,'debit',receipt_value,'credit',0,'description','Inventory received','source_reference',inventory_move_id::text),
        jsonb_build_object('account_id',grni_account,'debit',0,'credit',receipt_value,'description','Goods received not invoiced','source_reference',inventory_move_id::text)
      ),null);
  end if;
  return inventory_move_id;
end;
$$;
revoke all on function public.record_inventory_receipt_valued(uuid,uuid,uuid,numeric,numeric,text) from public,anon;
grant execute on function public.record_inventory_receipt_valued(uuid,uuid,uuid,numeric,numeric,text) to authenticated;

create or replace function public.apply_sale_inventory_valuation()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  before_qty numeric(14,3);
  after_qty numeric(14,3);
  before_value numeric(16,2);
  after_value numeric(16,2);
  avg_before numeric(16,6);
  cost_out numeric(16,2);
  avg_after numeric(16,6);
begin
  if NEW.movement_type<>'sale' then return NEW; end if;
  select quantity,carrying_value,average_unit_cost into before_qty,before_value,avg_before
  from public.inventory_valuation_balances
  where organization_id=NEW.organization_id and location_id=NEW.location_id and product_id=NEW.product_id
  for update;
  if not found then raise exception 'Inventory valuation balance missing; receive/open stock with cost before sale.' using errcode='23514'; end if;
  after_qty := before_qty+NEW.quantity_delta;
  if after_qty<0 then raise exception 'Inventory valuation cannot become negative.' using errcode='23514'; end if;
  if after_qty=0 then cost_out:=before_value; after_value:=0; avg_after:=0;
  else cost_out:=round((-NEW.quantity_delta)*avg_before,2); after_value:=round(before_value-cost_out,2); avg_after:=round(after_value/after_qty,6); end if;
  if after_value<0 then raise exception 'Inventory valuation would become negative.' using errcode='23514'; end if;
  update public.inventory_valuation_balances set quantity=after_qty,carrying_value=after_value,average_unit_cost=avg_after,updated_at=now()
  where organization_id=NEW.organization_id and location_id=NEW.location_id and product_id=NEW.product_id;
  insert into public.inventory_valuation_movements(organization_id,location_id,product_id,inventory_movement_id,movement_type,source_type,source_id,quantity_delta,unit_cost,value_delta,quantity_before,quantity_after,value_before,value_after,average_cost_after,note,created_by)
  values(NEW.organization_id,NEW.location_id,NEW.product_id,NEW.id,'sale','sale',NEW.reference_id,NEW.quantity_delta,avg_before,-cost_out,before_qty,after_qty,before_value,after_value,avg_after,NEW.note,NEW.created_by);
  return NEW;
end;
$$;
revoke all on function public.apply_sale_inventory_valuation() from public,anon,authenticated;
create trigger apply_sale_inventory_valuation_after_movement after insert on public.inventory_movements
for each row when (NEW.movement_type='sale') execute function public.apply_sale_inventory_valuation();

create or replace function public.post_completed_sale_to_ledger()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  org_model public.business_model;
  pay_method text;
  tender_account uuid;
  sales_account uuid;
  vat_account uuid;
  cogs_account uuid;
  inventory_account uuid;
  revenue_lines jsonb;
  cogs_lines jsonb;
  net_sales numeric(16,2);
  tax_amount numeric(16,2);
  total_due numeric(16,2);
  cogs_amount numeric(16,2);
begin
  if OLD.status is distinct from 'completed' and NEW.status='completed' then
    if not exists(select 1 from public.accounting_settings where organization_id=NEW.organization_id) then
      raise exception 'Accounting template is not initialized for this business.' using errcode='23514';
    end if;
    select business_model into org_model from public.organizations where id=NEW.organization_id;
    select method into pay_method from public.sale_payments where organization_id=NEW.organization_id and sale_id=NEW.id order by created_at desc limit 1;
    if pay_method is null then raise exception 'A completed sale must have a recorded tender.' using errcode='23514'; end if;
    select id into tender_account from public.chart_of_accounts where organization_id=NEW.organization_id and system_key=
      case pay_method when 'cash' then 'cash' when 'mpesa' then 'mpesa_clearing' when 'credit' then 'accounts_receivable' when 'bank_transfer' then 'bank' else 'payment_clearing' end and is_active;
    select id into sales_account from public.chart_of_accounts where organization_id=NEW.organization_id and system_key=case when org_model='wholesale' then 'wholesale_sales' else 'retail_sales' end and is_active;
    select id into vat_account from public.chart_of_accounts where organization_id=NEW.organization_id and system_key='vat_output' and is_active;
    if tender_account is null or sales_account is null or (NEW.tax_total>0 and vat_account is null) then raise exception 'Required sale accounting accounts are missing.' using errcode='23514'; end if;
    net_sales := round(NEW.subtotal-NEW.discount_total,2);
    tax_amount := NEW.tax_total;
    total_due := NEW.grand_total;
    if total_due<=0 or net_sales<0 then raise exception 'Sale totals are invalid for accounting.' using errcode='23514'; end if;
    revenue_lines := jsonb_build_array(
      jsonb_build_object('account_id',tender_account,'debit',total_due,'credit',0,'description','Sale tender','source_reference',NEW.receipt_number),
      jsonb_build_object('account_id',sales_account,'debit',0,'credit',net_sales,'description','Sales revenue','source_reference',NEW.receipt_number)
    );
    if tax_amount>0 then revenue_lines := revenue_lines || jsonb_build_array(jsonb_build_object('account_id',vat_account,'debit',0,'credit',tax_amount,'description','Output VAT','source_reference',NEW.receipt_number)); end if;
    perform public.post_accounting_journal_internal(NEW.organization_id,NEW.created_at::date,'Sale '||NEW.receipt_number,'sale',NEW.id,'revenue',revenue_lines,null);
    select coalesce(sum(-value_delta),0) into cogs_amount from public.inventory_valuation_movements
      where organization_id=NEW.organization_id and source_type='sale' and source_id=NEW.id and movement_type='sale';
    if cogs_amount>0 then
      select id into cogs_account from public.chart_of_accounts where organization_id=NEW.organization_id and system_key='cogs' and is_active;
      select id into inventory_account from public.chart_of_accounts where organization_id=NEW.organization_id and system_key='inventory' and is_active;
      if cogs_account is null or inventory_account is null then raise exception 'COGS/Inventory accounts are missing.' using errcode='23514'; end if;
      cogs_lines := jsonb_build_array(
        jsonb_build_object('account_id',cogs_account,'debit',cogs_amount,'credit',0,'description','Cost of goods sold','source_reference',NEW.receipt_number),
        jsonb_build_object('account_id',inventory_account,'debit',0,'credit',cogs_amount,'description','Inventory relieved','source_reference',NEW.receipt_number)
      );
      perform public.post_accounting_journal_internal(NEW.organization_id,NEW.created_at::date,'COGS for sale '||NEW.receipt_number,'sale',NEW.id,'cogs',cogs_lines,null);
    end if;
  end if;
  return NEW;
end;
$$;
revoke all on function public.post_completed_sale_to_ledger() from public,anon,authenticated;
create trigger post_completed_sale_to_ledger_after_completion after update of status on public.sales
for each row when (NEW.status='completed' and OLD.status is distinct from 'completed')
execute function public.post_completed_sale_to_ledger();

-- Legacy generic movement RPC must not bypass weighted-average valuation on client-originated receipts.
revoke all on function public.record_inventory_movement(uuid,uuid,uuid,text,numeric,text) from public,anon,authenticated;
grant execute on function public.record_inventory_movement(uuid,uuid,uuid,text,numeric,text) to service_role;
