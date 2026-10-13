-- SafariPOS accounting ledger foundation.
-- Additive only. Do not apply to a live business until the CPA policy and migration are reviewed.
create extension if not exists pgcrypto;

create table public.accounting_settings (
  organization_id uuid primary key references public.organizations(id) on delete restrict,
  accounting_basis text not null default 'accrual' check (accounting_basis = 'accrual'),
  inventory_costing_method text not null default 'moving_weighted_average' check (inventory_costing_method = 'moving_weighted_average'),
  negative_stock_policy text not null default 'block' check (negative_stock_policy in ('block','allow_warn')),
  locked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.chart_of_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  code text not null check (code ~ '^[0-9A-Z][0-9A-Z._-]{1,19}$'),
  name text not null check (char_length(trim(name)) between 2 and 120),
  account_type text not null check (account_type in ('asset','liability','equity','revenue','expense')),
  normal_balance text not null check (normal_balance in ('debit','credit')),
  is_control boolean not null default false,
  control_type text check (control_type in ('accounts_receivable','accounts_payable','inventory','vat_input','vat_output','mpesa_clearing','bank','cash','payment_clearing')),
  system_key text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, code),
  unique (organization_id, system_key),
  check ((is_control and control_type is not null) or not is_control)
);

create table public.accounting_periods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  period_name text not null,
  starts_on date not null,
  ends_on date not null,
  status text not null default 'open' check (status in ('open','closed')),
  closed_at timestamptz,
  closed_by uuid references auth.users(id) on delete set null,
  close_note text,
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,period_name),
  check (ends_on >= starts_on),
  check ((status='open' and closed_at is null) or (status='closed' and closed_at is not null))
);

create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  journal_number bigint not null,
  accounting_date date not null,
  description text not null check (char_length(trim(description)) between 2 and 500),
  source_type text not null check (char_length(trim(source_type)) between 2 and 80),
  source_id uuid not null,
  posting_purpose text not null default 'primary' check (char_length(trim(posting_purpose)) between 2 and 80),
  status text not null default 'draft' check (status in ('draft','posted','reversed')),
  reversed_entry_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  posted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  posted_at timestamptz,
  unique (organization_id,id),
  unique (organization_id,journal_number),
  unique (organization_id,source_type,source_id,posting_purpose),
  foreign key (organization_id,reversed_entry_id) references public.journal_entries(organization_id,id),
  check (reversed_entry_id is null or reversed_entry_id <> id),
  check ((status='draft' and posted_at is null) or (status in ('posted','reversed') and posted_at is not null))
);

create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  journal_entry_id uuid not null,
  line_number integer not null check (line_number > 0),
  account_id uuid not null,
  description text,
  debit numeric(16,2) not null default 0 check (debit >= 0),
  credit numeric(16,2) not null default 0 check (credit >= 0),
  source_reference text,
  created_at timestamptz not null default now(),
  foreign key (organization_id,journal_entry_id) references public.journal_entries(organization_id,id) on delete restrict,
  foreign key (organization_id,account_id) references public.chart_of_accounts(organization_id,id) on delete restrict,
  unique (journal_entry_id,line_number),
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);

create table public.accounting_audit_log (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  table_name text not null,
  record_id text not null,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  actor_id uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null default now(),
  before_data jsonb,
  after_data jsonb
);
create index journal_entries_org_date_idx on public.journal_entries(organization_id,accounting_date,journal_number);
create index journal_lines_org_account_idx on public.journal_lines(organization_id,account_id);
create index accounting_audit_org_time_idx on public.accounting_audit_log(organization_id,occurred_at desc);

create or replace function public.accounting_audit_row()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  row_data jsonb;
  target_org uuid;
  target_id text;
begin
  row_data := case when TG_OP='DELETE' then to_jsonb(OLD) else to_jsonb(NEW) end;
  target_org := (row_data->>'organization_id')::uuid;
  target_id := coalesce(row_data->>'id', row_data->>'journal_entry_id', row_data->>'code', target_org::text);
  insert into public.accounting_audit_log(organization_id,table_name,record_id,action,actor_id,before_data,after_data)
  values(target_org,TG_TABLE_NAME,target_id,TG_OP,auth.uid(),
    case when TG_OP in ('UPDATE','DELETE') then to_jsonb(OLD) else null end,
    case when TG_OP in ('INSERT','UPDATE') then to_jsonb(NEW) else null end);
  if TG_OP='DELETE' then return OLD; end if; return NEW;
end;
$$;

create or replace function public.guard_posted_journal()
returns trigger language plpgsql set search_path = ''
as $$
declare
  target_id uuid;
  target_status text;
begin
  if TG_TABLE_NAME='journal_entries' then
    if TG_OP='INSERT' and NEW.status <> 'draft' then raise exception 'Journals must be created as drafts and posted through the posting function.' using errcode='55000'; end if;
    if TG_OP='DELETE' and OLD.status <> 'draft' then raise exception 'Posted journal history is immutable; create a reversal.' using errcode='55000'; end if;
    if TG_OP='UPDATE' and OLD.status <> 'draft' then raise exception 'Posted journal history is immutable; create a reversal.' using errcode='55000'; end if;
    if TG_OP='UPDATE' and NEW.status='posted' and OLD.status='draft' then
      if (select count(*) from public.journal_lines l where l.organization_id=NEW.organization_id and l.journal_entry_id=NEW.id) < 2
        or (select coalesce(sum(l.debit),0) from public.journal_lines l where l.organization_id=NEW.organization_id and l.journal_entry_id=NEW.id)
         <> (select coalesce(sum(l.credit),0) from public.journal_lines l where l.organization_id=NEW.organization_id and l.journal_entry_id=NEW.id) then
        raise exception 'Journal must contain at least two lines and equal debit/credit totals.' using errcode='23514';
      end if;
    end if;
    if TG_OP='DELETE' then return OLD; end if; return NEW;
  end if;
  target_id := case when TG_OP='INSERT' then NEW.journal_entry_id else OLD.journal_entry_id end;
  select status into target_status from public.journal_entries where id=target_id;
  if target_status in ('posted','reversed') then raise exception 'Posted journal lines are immutable; create a reversal.' using errcode='55000'; end if;
  if TG_OP='UPDATE' and NEW.journal_entry_id <> OLD.journal_entry_id then
    select status into target_status from public.journal_entries where id=NEW.journal_entry_id;
    if target_status in ('posted','reversed') then raise exception 'Posted journal lines are immutable.' using errcode='55000'; end if;
  end if;
  if TG_OP='DELETE' then return OLD; end if; return NEW;
end;
$$;

create or replace function public.guard_accounting_policy()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if TG_OP='UPDATE' then
    if OLD.locked_at is not null and NEW.locked_at is null then
      raise exception 'Accounting policy lock cannot be removed after first posting.' using errcode='55000';
    end if;
    if OLD.locked_at is not null and (NEW.accounting_basis is distinct from OLD.accounting_basis or NEW.inventory_costing_method is distinct from OLD.inventory_costing_method) then
      raise exception 'Accounting basis and costing method are locked after first posting.' using errcode='55000';
    end if;
    NEW.updated_at := now();
  end if;
  return NEW;
end;
$$;

create or replace function public.guard_chart_account()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if TG_OP='DELETE' and exists(select 1 from public.journal_lines where organization_id=OLD.organization_id and account_id=OLD.id) then
    raise exception 'An account referenced by journal history cannot be deleted; deactivate it instead.' using errcode='55000';
  end if;
  if TG_OP='UPDATE' and OLD.system_key is not null and
    (NEW.code is distinct from OLD.code or NEW.account_type is distinct from OLD.account_type or NEW.normal_balance is distinct from OLD.normal_balance or NEW.system_key is distinct from OLD.system_key or NEW.control_type is distinct from OLD.control_type) then
    raise exception 'System account code, type and control mapping are protected.' using errcode='55000';
  end if;
  if TG_OP='UPDATE' then NEW.updated_at := now(); end if;
  if TG_OP='DELETE' then return OLD; end if; return NEW;
end;
$$;

create trigger journal_entries_immutable before insert or update or delete on public.journal_entries for each row execute function public.guard_posted_journal();
create trigger journal_lines_immutable before insert or update or delete on public.journal_lines for each row execute function public.guard_posted_journal();
create trigger accounting_settings_guard before update on public.accounting_settings for each row execute function public.guard_accounting_policy();
create trigger chart_account_guard before update or delete on public.chart_of_accounts for each row execute function public.guard_chart_account();

create trigger audit_accounting_settings after insert or update or delete on public.accounting_settings for each row execute function public.accounting_audit_row();
create trigger audit_chart_of_accounts after insert or update or delete on public.chart_of_accounts for each row execute function public.accounting_audit_row();
create trigger audit_accounting_periods after insert or update or delete on public.accounting_periods for each row execute function public.accounting_audit_row();
create trigger audit_journal_entries after insert or update or delete on public.journal_entries for each row execute function public.accounting_audit_row();
create trigger audit_journal_lines after insert or update or delete on public.journal_lines for each row execute function public.accounting_audit_row();

alter table public.accounting_settings enable row level security;
alter table public.chart_of_accounts enable row level security;
alter table public.accounting_periods enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
alter table public.accounting_audit_log enable row level security;

create policy "Accounting members read settings" on public.accounting_settings for select to authenticated using (public.is_organization_member(organization_id));
create policy "Accounting owners manage settings" on public.accounting_settings for all to authenticated
using (exists(select 1 from public.organization_members m where m.organization_id=accounting_settings.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin')))
with check (exists(select 1 from public.organization_members m where m.organization_id=accounting_settings.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin')));
create policy "Accounting members read chart" on public.chart_of_accounts for select to authenticated using (public.is_organization_member(organization_id));
create policy "Accounting owners manage chart" on public.chart_of_accounts for insert to authenticated with check (exists(select 1 from public.organization_members m where m.organization_id=chart_of_accounts.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin')));
create policy "Accounting owners update chart" on public.chart_of_accounts for update to authenticated
using (exists(select 1 from public.organization_members m where m.organization_id=chart_of_accounts.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin')))
with check (exists(select 1 from public.organization_members m where m.organization_id=chart_of_accounts.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin')));
create policy "Accounting members read periods" on public.accounting_periods for select to authenticated using (public.is_organization_member(organization_id));
create policy "Accounting members read journals" on public.journal_entries for select to authenticated using (public.is_organization_member(organization_id));
create policy "Accounting members read lines" on public.journal_lines for select to authenticated using (public.is_organization_member(organization_id));
create policy "Accounting owners read audit" on public.accounting_audit_log for select to authenticated using (exists(select 1 from public.organization_members m where m.organization_id=accounting_audit_log.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin')));

revoke insert,update,delete on public.journal_entries,public.journal_lines,public.accounting_audit_log from anon,authenticated;
revoke delete on public.chart_of_accounts from anon,authenticated;
revoke all on function public.accounting_audit_row() from public,anon,authenticated;
revoke all on function public.guard_posted_journal() from public,anon,authenticated;
revoke all on function public.guard_accounting_policy() from public,anon,authenticated;
revoke all on function public.guard_chart_account() from public,anon,authenticated;

create or replace function public.initialize_safaripos_accounting(p_organization_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare caller uuid := auth.uid();
begin
  if caller is null or not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=caller and m.role in ('owner','admin')) then
    raise exception 'Only a workspace owner/admin can initialize accounting.' using errcode='42501';
  end if;
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
revoke all on function public.initialize_safaripos_accounting(uuid) from public,anon;
grant execute on function public.initialize_safaripos_accounting(uuid) to authenticated;

create or replace function public.post_accounting_journal(
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
  caller_role public.business_role;
  service_call boolean := coalesce(current_setting('request.jwt.claim.role',true),'')='service_role';
  journal_id uuid;
  next_number bigint;
  line jsonb;
  line_no integer := 0;
  total_debit numeric(16,2);
  total_credit numeric(16,2);
  existing_status text;
begin
  if not service_call then
    if caller is null then raise exception 'Authentication required' using errcode='28000'; end if;
    select role into caller_role from public.organization_members where organization_id=p_organization_id and user_id=caller;
    if caller_role is null or caller_role not in ('owner','admin','manager') then raise exception 'Not authorized to post accounting journals' using errcode='42501'; end if;
  end if;
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
revoke all on function public.post_accounting_journal(uuid,date,text,text,uuid,text,jsonb,uuid) from public,anon;
grant execute on function public.post_accounting_journal(uuid,date,text,text,uuid,text,jsonb,uuid) to authenticated,service_role;

create or replace function public.close_accounting_period(p_organization_id uuid,p_period_id uuid,p_note text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare caller uuid := auth.uid();
begin
  if caller is null or not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=caller and m.role in ('owner','admin')) then
    raise exception 'Only a workspace owner/admin can close a period.' using errcode='42501';
  end if;
  if not exists(select 1 from public.accounting_periods where id=p_period_id and organization_id=p_organization_id and status='open') then
    raise exception 'Open accounting period not found.' using errcode='P0002';
  end if;
  if exists(select 1 from public.journal_entries j where j.organization_id=p_organization_id and j.status='draft') then
    raise exception 'Draft journals must be resolved before close.' using errcode='23514';
  end if;
  update public.accounting_periods set status='closed',closed_at=now(),closed_by=caller,close_note=left(p_note,500)
    where id=p_period_id and organization_id=p_organization_id and status='open';
end;
$$;
revoke all on function public.close_accounting_period(uuid,uuid,text) from public,anon;
grant execute on function public.close_accounting_period(uuid,uuid,text) to authenticated;

revoke insert,update,delete on public.accounting_periods from anon,authenticated;


create or replace function public.create_accounting_period(
  p_organization_id uuid,
  p_period_name text,
  p_starts_on date,
  p_ends_on date
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare caller uuid := auth.uid(); period_id uuid;
begin
  if caller is null or not exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=caller and m.role in ('owner','admin')) then
    raise exception 'Only a workspace owner/admin can create accounting periods.' using errcode='42501';
  end if;
  if p_starts_on is null or p_ends_on is null or p_ends_on<p_starts_on or length(trim(coalesce(p_period_name,'')))<2 then
    raise exception 'A valid period name, start date and end date are required.' using errcode='22023';
  end if;
  if exists(select 1 from public.accounting_periods p where p.organization_id=p_organization_id and daterange(p.starts_on,p.ends_on,'[]') && daterange(p_starts_on,p_ends_on,'[]')) then
    raise exception 'Accounting periods for one business cannot overlap.' using errcode='23514';
  end if;
  insert into public.accounting_periods(organization_id,period_name,starts_on,ends_on)
  values(p_organization_id,left(trim(p_period_name),80),p_starts_on,p_ends_on) returning id into period_id;
  return period_id;
end;
$$;
revoke all on function public.create_accounting_period(uuid,text,date,date) from public,anon;
grant execute on function public.create_accounting_period(uuid,text,date,date) to authenticated;

create or replace function public.reverse_accounting_journal(
  p_organization_id uuid,
  p_original_journal_id uuid,
  p_reversal_date date,
  p_reason text
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare original public.journal_entries%rowtype; reversal_id uuid; reverse_lines jsonb;
begin
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'A meaningful reversal reason is required.' using errcode='22023'; end if;
  select * into original from public.journal_entries
    where organization_id=p_organization_id and id=p_original_journal_id and status='posted';
  if not found then raise exception 'Only an existing posted journal can be reversed.' using errcode='P0002'; end if;
  if original.reversed_entry_id is not null or original.source_type='reversal' then
    raise exception 'A reversal journal cannot itself be reversed through this function.' using errcode='23514';
  end if;
  select jsonb_agg(jsonb_build_object(
    'account_id',l.account_id,
    'debit',l.credit,
    'credit',l.debit,
    'description',coalesce(l.description,'Reversal: ') || ' [reversal]',
    'source_reference',coalesce(l.source_reference,original.source_type||':'||original.source_id::text)
  ) order by l.line_number)
  into reverse_lines from public.journal_lines l
  where l.organization_id=p_organization_id and l.journal_entry_id=original.id;
  if reverse_lines is null then raise exception 'Original journal has no lines.' using errcode='23514'; end if;
  reversal_id := public.post_accounting_journal(
    p_organization_id,
    p_reversal_date,
    'Reversal of journal '||original.journal_number||': '||left(trim(p_reason),400),
    'reversal',
    original.id,
    'reversal',
    reverse_lines,
    original.id
  );
  return reversal_id;
end;
$$;
revoke all on function public.reverse_accounting_journal(uuid,uuid,date,text) from public,anon;
grant execute on function public.reverse_accounting_journal(uuid,uuid,date,text) to authenticated;
