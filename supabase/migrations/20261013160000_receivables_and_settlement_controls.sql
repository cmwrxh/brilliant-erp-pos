-- SafariPOS receivables, supplier payables and M-PESA settlement controls.
-- Additive only. No live provider calls or automatic production enablement.
create table public.document_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  document_id uuid not null,
  payment_id uuid not null,
  amount numeric(16,2) not null check (amount > 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (organization_id,payment_id,document_id),
  foreign key (organization_id,document_id) references public.sales_documents(organization_id,id) on delete restrict,
  foreign key (organization_id,payment_id) references public.document_payments(organization_id,id) on delete restrict
);
create index document_payment_allocations_document_idx on public.document_payment_allocations(organization_id,document_id,created_at desc);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  supplier_code text,
  name text not null check (char_length(trim(name)) between 2 and 200),
  kra_pin text,
  phone text,
  email text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,supplier_code),
  foreign key (organization_id) references public.organizations(id) on delete restrict
);
create table public.supplier_bills (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  supplier_id uuid not null,
  supplier_invoice_number text not null check (char_length(trim(supplier_invoice_number)) between 1 and 100),
  bill_date date not null,
  due_date date,
  status text not null default 'posted' check (status in ('posted','partially_paid','paid','void')),
  currency_code char(3) not null default 'KES',
  subtotal numeric(16,2) not null check (subtotal >= 0),
  input_tax numeric(16,2) not null default 0 check (input_tax >= 0),
  total_amount numeric(16,2) generated always as (subtotal+input_tax) stored,
  amount_paid numeric(16,2) not null default 0 check (amount_paid >= 0),
  source_fingerprint text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,supplier_id,supplier_invoice_number),
  foreign key (organization_id,supplier_id) references public.suppliers(organization_id,id) on delete restrict,
  check (amount_paid <= subtotal+input_tax),
  check (due_date is null or due_date >= bill_date)
);
create index supplier_bills_due_idx on public.supplier_bills(organization_id,due_date) where status in ('posted','partially_paid');
create table public.supplier_bill_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  bill_id uuid not null,
  line_number integer not null check (line_number > 0),
  description text not null check (char_length(trim(description)) between 2 and 500),
  account_code text not null,
  net_amount numeric(16,2) not null check (net_amount >= 0),
  tax_amount numeric(16,2) not null default 0 check (tax_amount >= 0),
  created_at timestamptz not null default now(),
  unique (organization_id,bill_id,line_number),
  foreign key (organization_id,bill_id) references public.supplier_bills(organization_id,id) on delete restrict
);
create table public.supplier_bill_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  bill_id uuid not null,
  tender_type text not null check (tender_type in ('cash','mpesa','bank_transfer','other')),
  provider_reference text,
  idempotency_key text not null,
  amount numeric(16,2) not null check (amount > 0),
  paid_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,idempotency_key),
  unique (organization_id,tender_type,provider_reference),
  foreign key (organization_id,bill_id) references public.supplier_bills(organization_id,id) on delete restrict
);
create table public.mpesa_settlements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  settlement_reference text not null,
  period_start timestamptz not null,
  period_end timestamptz not null,
  gross_amount numeric(16,2) not null check (gross_amount > 0),
  fee_amount numeric(16,2) not null default 0 check (fee_amount >= 0),
  net_amount numeric(16,2) not null check (net_amount > 0),
  bank_reference text,
  status text not null default 'recorded' check (status in ('recorded','matched','variance','posted')),
  journal_entry_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,settlement_reference),
  foreign key (organization_id,journal_entry_id) references public.journal_entries(organization_id,id) on delete restrict,
  check (period_end >= period_start),
  check (round(gross_amount-fee_amount,2)=net_amount)
);
create table public.mpesa_settlement_matches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  settlement_id uuid not null,
  payment_id uuid not null,
  matched_amount numeric(16,2) not null check (matched_amount > 0),
  matched_by uuid references auth.users(id) on delete set null,
  matched_at timestamptz not null default now(),
  unique (organization_id,settlement_id,payment_id),
  foreign key (organization_id,settlement_id) references public.mpesa_settlements(organization_id,id) on delete restrict,
  foreign key (organization_id,payment_id) references public.document_payments(organization_id,id) on delete restrict
);

do $body$
declare t text;
begin
  foreach t in array array['document_payment_allocations','suppliers','supplier_bills','supplier_bill_lines','supplier_bill_payments','mpesa_settlements','mpesa_settlement_matches'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from anon',t);
    execute format('revoke insert,update,delete,truncate,references,trigger on public.%I from authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_organization_member(organization_id))','Tenant members read '||t,t);
  end loop;
end
$body$;

create or replace function public.record_document_payment(
  p_organization_id uuid,
  p_document_id uuid,
  p_tender_type text,
  p_amount numeric,
  p_idempotency_key text,
  p_provider text default null,
  p_provider_reference text default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  doc public.sales_documents%rowtype;
  payment_id uuid;
  tender_key text;
  tender_account uuid;
  ar_account uuid;
  journal_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  select role::text into caller_role from public.organization_members
    where organization_id=p_organization_id and user_id=caller_id;
  if caller_role is null or caller_role not in ('owner','admin','manager','cashier') then
    raise exception 'Not authorized to record customer payments.' using errcode='42501';
  end if;
  if p_tender_type not in ('cash','mpesa','bank_transfer','card','other')
     or p_amount is null or p_amount<=0 or p_amount>1000000000
     or p_idempotency_key is null or length(trim(p_idempotency_key))<8 then
    raise exception 'Valid tender, amount and idempotency key are required.' using errcode='22023';
  end if;
  if p_tender_type='mpesa' and (p_provider_reference is null or length(trim(p_provider_reference))<4) then
    raise exception 'Confirmed M-PESA reference is required; an STK request is not a payment.' using errcode='22023';
  end if;
  select * into doc from public.sales_documents
   where organization_id=p_organization_id and id=p_document_id for update;
  if not found or doc.document_type='credit_note' or doc.status in ('draft','void','credited') then
    raise exception 'Only an issued sale or invoice can receive payment.' using errcode='23514';
  end if;
  select id into payment_id from public.document_payments
   where organization_id=p_organization_id and idempotency_key=p_idempotency_key;
  if payment_id is not null then return payment_id; end if;
  if p_amount > doc.grand_total-doc.amount_paid then
    raise exception 'Payment exceeds the outstanding balance.' using errcode='23514';
  end if;
  tender_key := case p_tender_type
    when 'cash' then 'cash'
    when 'mpesa' then 'mpesa_clearing'
    when 'bank_transfer' then 'bank'
    when 'card' then 'payment_clearing'
    else 'cash' end;
  select id into tender_account from public.chart_of_accounts
   where organization_id=p_organization_id and system_key=tender_key and is_active;
  select id into ar_account from public.chart_of_accounts
   where organization_id=p_organization_id and system_key='accounts_receivable' and is_active;
  if tender_account is null or ar_account is null then
    raise exception 'Initialize the business chart of accounts before recording payments.' using errcode='23514';
  end if;
  insert into public.document_payments(organization_id,document_id,tender_type,provider,provider_reference,
    idempotency_key,amount,currency_code,status,received_amount,confirmed_at)
  values(p_organization_id,p_document_id,p_tender_type,p_provider,p_provider_reference,
    p_idempotency_key,p_amount,doc.currency_code,'succeeded',p_amount,now())
  returning id into payment_id;
  insert into public.document_payment_allocations(organization_id,document_id,payment_id,amount,created_by)
  values(p_organization_id,p_document_id,payment_id,p_amount,caller_id);
  update public.sales_documents set amount_paid=amount_paid+p_amount,
    status=case when amount_paid+p_amount>=grand_total then 'paid' else 'partially_paid' end,
    updated_at=now()
  where organization_id=p_organization_id and id=p_document_id;
  journal_id := public.post_accounting_journal_internal(
    p_organization_id,current_date,'Customer payment for '||doc.document_number,
    'document_payment',payment_id,'receivable_payment',
    jsonb_build_array(
      jsonb_build_object('account_id',tender_account,'debit',p_amount,'credit',0,'description','Customer funds received','source_reference',coalesce(p_provider_reference,p_idempotency_key)),
      jsonb_build_object('account_id',ar_account,'debit',0,'credit',p_amount,'description','Clear customer receivable','source_reference',doc.document_number)
    ),null
  );
  insert into public.document_ledger_postings(organization_id,document_id,journal_entry_id,source_type,source_id,posting_purpose,posted_at)
  values(p_organization_id,p_document_id,journal_id,'document_payment',payment_id,'receivable_payment',now())
  on conflict (organization_id,source_type,source_id,posting_purpose) do nothing;
  return payment_id;
end;
$$;
revoke all on function public.record_document_payment(uuid,uuid,text,numeric,text,text,text) from public,anon;
grant execute on function public.record_document_payment(uuid,uuid,text,numeric,text,text,text) to authenticated;

create or replace function public.record_mpesa_settlement(
  p_organization_id uuid,
  p_settlement_reference text,
  p_period_start timestamptz,
  p_period_end timestamptz,
  p_gross_amount numeric,
  p_fee_amount numeric,
  p_net_amount numeric,
  p_bank_reference text default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  settlement_id uuid;
  clearing_account uuid;
  bank_account uuid;
  fee_account uuid;
  journal_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  select role::text into caller_role from public.organization_members where organization_id=p_organization_id and user_id=caller_id;
  if caller_role is null or caller_role not in ('owner','admin','manager') then raise exception 'Not authorized to reconcile settlements.' using errcode='42501'; end if;
  if length(trim(coalesce(p_settlement_reference,'')))<4 or p_period_start is null or p_period_end<p_period_start
    or p_gross_amount<=0 or p_fee_amount<0 or p_net_amount<=0 or round(p_gross_amount-p_fee_amount,2)<>p_net_amount then
    raise exception 'Settlement period and amounts are invalid; gross less fees must equal net.' using errcode='22023';
  end if;
  select id into settlement_id from public.mpesa_settlements
   where organization_id=p_organization_id and settlement_reference=p_settlement_reference;
  if settlement_id is not null then return settlement_id; end if;
  select id into clearing_account from public.chart_of_accounts where organization_id=p_organization_id and system_key='mpesa_clearing' and is_active;
  select id into bank_account from public.chart_of_accounts where organization_id=p_organization_id and system_key='bank' and is_active;
  select id into fee_account from public.chart_of_accounts where organization_id=p_organization_id and system_key='payment_fees' and is_active;
  if clearing_account is null or bank_account is null or fee_account is null then
    raise exception 'Required M-PESA clearing, bank and fee accounts are missing.' using errcode='23514';
  end if;
  insert into public.mpesa_settlements(organization_id,settlement_reference,period_start,period_end,gross_amount,fee_amount,net_amount,bank_reference,created_by)
  values(p_organization_id,p_settlement_reference,p_period_start,p_period_end,p_gross_amount,p_fee_amount,p_net_amount,p_bank_reference,caller_id)
  returning id into settlement_id;
  journal_id := public.post_accounting_journal_internal(
    p_organization_id,(p_period_end at time zone 'Africa/Nairobi')::date,
    'M-PESA settlement '||p_settlement_reference,'mpesa_settlement',settlement_id,'settlement',
    jsonb_build_array(
      jsonb_build_object('account_id',bank_account,'debit',p_net_amount,'credit',0,'description','Net M-PESA bank settlement','source_reference',coalesce(p_bank_reference,p_settlement_reference)),
      jsonb_build_object('account_id',fee_account,'debit',p_fee_amount,'credit',0,'description','M-PESA processing fees','source_reference',p_settlement_reference),
      jsonb_build_object('account_id',clearing_account,'debit',0,'credit',p_gross_amount,'description','Clear gross M-PESA receipts','source_reference',p_settlement_reference)
    ),null
  );
  update public.mpesa_settlements set journal_entry_id=journal_id,status='posted'
   where organization_id=p_organization_id and id=settlement_id;
  return settlement_id;
end;
$$;
revoke all on function public.record_mpesa_settlement(uuid,text,timestamptz,timestamptz,numeric,numeric,numeric,text) from public,anon;
grant execute on function public.record_mpesa_settlement(uuid,text,timestamptz,timestamptz,numeric,numeric,numeric,text) to authenticated;

create or replace function public.queue_document_etims_submission(
  p_organization_id uuid,
  p_document_id uuid,
  p_submission_mode text,
  p_idempotency_key text,
  p_request_fingerprint text
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  doc public.sales_documents%rowtype;
  submission_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  select role::text into caller_role from public.organization_members where organization_id=p_organization_id and user_id=caller_id;
  if caller_role is null or caller_role not in ('owner','admin','manager') then raise exception 'Not authorized to queue tax documents.' using errcode='42501'; end if;
  if p_submission_mode not in ('OSCU','VSCU','other') or length(trim(coalesce(p_idempotency_key,'')))<8
     or length(trim(coalesce(p_request_fingerprint,'')))<16 then
    raise exception 'Submission mode, idempotency key and request fingerprint are required.' using errcode='22023';
  end if;
  select * into doc from public.sales_documents where organization_id=p_organization_id and id=p_document_id for update;
  if not found or doc.document_type not in ('sale','invoice') or doc.status in ('draft','void','credited') then
    raise exception 'Only an issued sale or invoice can be submitted to eTIMS.' using errcode='23514';
  end if;
  select id into submission_id from public.document_etims_submissions
   where organization_id=p_organization_id and idempotency_key=p_idempotency_key;
  if submission_id is not null then return submission_id; end if;
  insert into public.document_etims_submissions(organization_id,document_id,submission_mode,idempotency_key,request_fingerprint,status)
  values(p_organization_id,p_document_id,p_submission_mode,p_idempotency_key,p_request_fingerprint,'queued')
  returning id into submission_id;
  return submission_id;
end;
$$;
revoke all on function public.queue_document_etims_submission(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.queue_document_etims_submission(uuid,uuid,text,text,text) to authenticated;
