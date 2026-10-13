-- SafariPOS unified sales documents foundation.
-- Additive schema only. This file is committed for local CI/review; do not apply to a live project without explicit approval.
-- Existing sales, sale_items, sale_payments, etims_invoices and immutable journals remain authoritative
-- for legacy transactions until an explicit expand/contract migration backfills and switches callers.

create table public.sales_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  document_number text not null check (char_length(trim(document_number)) between 1 and 80),
  document_type text not null check (document_type in ('sale','invoice','credit_note')),
  status text not null default 'draft' check (status in ('draft','issued','sent','partially_paid','paid','overdue','void','credited')),
  customer_id uuid,
  location_id uuid,
  source_document_id uuid,
  legacy_sale_id uuid,
  currency_code char(3) not null default 'KES',
  issued_at timestamptz,
  due_at timestamptz,
  subtotal numeric(16,2) not null default 0 check (subtotal >= 0),
  discount_total numeric(16,2) not null default 0 check (discount_total >= 0),
  tax_total numeric(16,2) not null default 0 check (tax_total >= 0),
  grand_total numeric(16,2) not null default 0 check (grand_total >= 0),
  amount_paid numeric(16,2) not null default 0 check (amount_paid >= 0),
  balance_due numeric(16,2) generated always as (greatest(grand_total - amount_paid, 0::numeric)) stored,
  created_by uuid references auth.users(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  idempotency_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,document_number),
  unique (organization_id,legacy_sale_id),
  unique (organization_id,idempotency_key),
  foreign key (organization_id,customer_id) references public.customers(organization_id,id) on delete restrict,
  foreign key (organization_id,location_id) references public.locations(organization_id,id) on delete restrict,
  foreign key (organization_id,source_document_id) references public.sales_documents(organization_id,id) on delete restrict,
  foreign key (organization_id,legacy_sale_id) references public.sales(organization_id,id) on delete restrict,
  check ((document_type='credit_note' and source_document_id is not null) or document_type<>'credit_note'),
  check ((status='void' and voided_at is not null) or status<>'void'),
  check (amount_paid <= grand_total),
  check (due_at is null or issued_at is null or due_at >= issued_at)
);
create index sales_documents_org_created_idx on public.sales_documents(organization_id,created_at desc);
create index sales_documents_org_customer_due_idx on public.sales_documents(organization_id,customer_id,due_at) where status not in ('void','credited');
create index sales_documents_org_status_idx on public.sales_documents(organization_id,status,created_at desc);

create table public.sales_document_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  document_id uuid not null,
  line_number integer not null check (line_number > 0),
  product_id uuid,
  description_snapshot text not null check (char_length(trim(description_snapshot)) between 1 and 500),
  sku_snapshot text,
  unit_of_measure text not null default 'each',
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(16,4) not null check (unit_price >= 0),
  discount_amount numeric(16,2) not null default 0 check (discount_amount >= 0),
  tax_code text,
  tax_rate_snapshot numeric(7,4) not null default 0 check (tax_rate_snapshot between 0 and 100),
  taxable_base numeric(16,2) not null default 0 check (taxable_base >= 0),
  tax_amount numeric(16,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(16,2) not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,document_id,line_number),
  foreign key (organization_id,document_id) references public.sales_documents(organization_id,id) on delete restrict,
  foreign key (organization_id,product_id) references public.products(organization_id,id) on delete restrict,
  check (discount_amount <= round(quantity * unit_price,2))
);
create index sales_document_lines_document_idx on public.sales_document_lines(organization_id,document_id,line_number);

create table public.sales_document_tax_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  document_id uuid not null,
  document_line_id uuid,
  tax_code_snapshot text not null,
  tax_rate_snapshot numeric(7,4) not null check (tax_rate_snapshot between 0 and 100),
  tax_treatment text not null check (tax_treatment in ('taxable','zero_rated','exempt','out_of_scope','reverse_charge','other')),
  taxable_base numeric(16,2) not null check (taxable_base >= 0),
  tax_amount numeric(16,2) not null check (tax_amount >= 0),
  created_at timestamptz not null default now(),
  foreign key (organization_id,document_id) references public.sales_documents(organization_id,id) on delete restrict,
  foreign key (organization_id,document_line_id) references public.sales_document_lines(organization_id,id) on delete restrict
);
create index sales_document_tax_lines_document_idx on public.sales_document_tax_lines(organization_id,document_id);

alter table public.sale_payments add constraint sale_payments_organization_id_id_key unique (organization_id,id);

create table public.document_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  document_id uuid not null,
  tender_type text not null check (tender_type in ('cash','mpesa','card','bank_transfer','credit','other')),
  provider text,
  provider_reference text,
  idempotency_key text not null,
  amount numeric(16,2) not null check (amount > 0),
  currency_code char(3) not null default 'KES',
  status text not null default 'pending' check (status in ('pending','succeeded','failed','reversed','partially_refunded','refunded')),
  received_amount numeric(16,2) not null default 0 check (received_amount >= 0),
  refunded_amount numeric(16,2) not null default 0 check (refunded_amount >= 0),
  legacy_sale_payment_id uuid,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,idempotency_key),
  unique (organization_id,legacy_sale_payment_id),
  foreign key (organization_id,document_id) references public.sales_documents(organization_id,id) on delete restrict,
  foreign key (organization_id,legacy_sale_payment_id) references public.sale_payments(organization_id,id) on delete restrict,
  check (received_amount <= amount),
  check (refunded_amount <= received_amount)
);
create index document_payments_document_idx on public.document_payments(organization_id,document_id,created_at desc);
create unique index document_payments_provider_reference_idx on public.document_payments(organization_id,provider,provider_reference)
  where provider is not null and provider_reference is not null;

create table public.document_credit_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  credit_note_document_id uuid not null,
  original_document_id uuid not null,
  amount numeric(16,2) not null check (amount > 0),
  reason text not null check (char_length(trim(reason)) between 2 and 500),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (organization_id,credit_note_document_id,original_document_id),
  foreign key (organization_id,credit_note_document_id) references public.sales_documents(organization_id,id) on delete restrict,
  foreign key (organization_id,original_document_id) references public.sales_documents(organization_id,id) on delete restrict,
  check (credit_note_document_id <> original_document_id)
);

create table public.document_ledger_postings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  document_id uuid not null,
  journal_entry_id uuid,
  source_type text not null check (char_length(trim(source_type)) between 2 and 80),
  source_id uuid not null,
  posting_purpose text not null check (char_length(trim(posting_purpose)) between 2 and 80),
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (organization_id,source_type,source_id,posting_purpose),
  foreign key (organization_id,document_id) references public.sales_documents(organization_id,id) on delete restrict,
  foreign key (organization_id,journal_entry_id) references public.journal_entries(organization_id,id) on delete restrict
);
create index document_ledger_postings_document_idx on public.document_ledger_postings(organization_id,document_id);

create table public.document_etims_submissions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  document_id uuid not null,
  legacy_etims_invoice_id uuid,
  submission_mode text check (submission_mode in ('OSCU','VSCU','other')),
  status text not null default 'queued' check (status in ('queued','submitting','accepted','rejected','retry_wait','failed','cancelled')),
  idempotency_key text not null,
  request_fingerprint text,
  kra_control_unit_invoice_number text,
  kra_receipt_number text,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  next_attempt_at timestamptz,
  submitted_at timestamptz,
  accepted_at timestamptz,
  error_code text,
  error_message text,
  safe_response_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,idempotency_key),
  foreign key (organization_id,document_id) references public.sales_documents(organization_id,id) on delete restrict,
  foreign key (organization_id,legacy_etims_invoice_id) references public.etims_invoices(organization_id,id) on delete restrict,
  check ((status='accepted' and accepted_at is not null) or status<>'accepted')
);
create index document_etims_due_idx on public.document_etims_submissions(status,next_attempt_at) where status in ('queued','retry_wait');
create index document_etims_document_idx on public.document_etims_submissions(organization_id,document_id,created_at desc);

create table public.document_delivery_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  document_id uuid not null,
  channel text not null check (channel in ('email','sms','whatsapp','link')),
  recipient_reference text,
  template_key text,
  language_code text not null default 'en' check (language_code in ('en','sw')),
  provider_message_id text,
  status text not null default 'queued' check (status in ('queued','sent','delivered','failed','cancelled')),
  estimated_cost numeric(12,4) check (estimated_cost is null or estimated_cost >= 0),
  actual_cost numeric(12,4) check (actual_cost is null or actual_cost >= 0),
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,idempotency_key),
  foreign key (organization_id,document_id) references public.sales_documents(organization_id,id) on delete restrict
);
create index document_delivery_queue_idx on public.document_delivery_events(status,created_at) where status='queued';

create table public.invoice_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  template_name text not null check (char_length(trim(template_name)) between 1 and 100),
  logo_asset_path text,
  brand_config jsonb not null default '{}'::jsonb,
  business_details_snapshot jsonb not null default '{}'::jsonb,
  footer_text text,
  version integer not null default 1 check (version > 0),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,template_name,version)
);
create unique index invoice_templates_one_default_idx on public.invoice_templates(organization_id) where is_default;

create table public.invoice_reminder_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  stage text not null check (stage in ('before_due','due_date','overdue')),
  offset_days integer not null default 0 check (offset_days between -365 and 365),
  enabled boolean not null default false,
  local_send_start time not null default time '08:00',
  local_send_end time not null default time '18:00',
  timezone text not null default 'Africa/Nairobi',
  language_code text not null default 'en' check (language_code in ('en','sw')),
  channel text not null check (channel in ('email','sms','whatsapp')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,stage,channel),
  check (local_send_end > local_send_start)
);

create table public.recurring_invoice_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  customer_id uuid not null,
  schedule_name text not null check (char_length(trim(schedule_name)) between 1 and 120),
  cadence text not null check (cadence in ('weekly','monthly','quarterly','yearly')),
  next_issue_at timestamptz not null,
  due_days_after_issue integer not null default 0 check (due_days_after_issue between 0 and 365),
  template_payload jsonb not null,
  enabled boolean not null default true,
  lease_owner text,
  lease_expires_at timestamptz,
  last_occurrence_key text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,customer_id) references public.customers(organization_id,id) on delete restrict,
  check ((lease_owner is null and lease_expires_at is null) or (lease_owner is not null and lease_expires_at is not null))
);
create index recurring_invoice_due_idx on public.recurring_invoice_schedules(next_issue_at) where enabled;

create table public.customer_contact_preferences (
  organization_id uuid not null references public.organizations(id) on delete restrict,
  customer_id uuid not null,
  channel text not null check (channel in ('email','sms','whatsapp')),
  consent_status text not null default 'unknown' check (consent_status in ('unknown','opted_in','opted_out')),
  consent_recorded_at timestamptz,
  source text,
  updated_at timestamptz not null default now(),
  primary key (organization_id,customer_id,channel),
  foreign key (organization_id,customer_id) references public.customers(organization_id,id) on delete restrict
);

create table public.support_access_grants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  granted_by uuid not null references auth.users(id) on delete restrict,
  support_actor_id uuid not null references auth.users(id) on delete restrict,
  reason text not null check (char_length(trim(reason)) between 5 and 500),
  granted_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > granted_at),
  check (revoked_at is null or revoked_at >= granted_at)
);
create index support_access_grants_active_idx on public.support_access_grants(organization_id,expires_at) where revoked_at is null;

-- Read access is tenant-scoped. Writes are reserved for reviewed server-side workflows;
-- no browser role gets direct INSERT/UPDATE/DELETE on financial records.
do $body$
declare t text;
begin
  foreach t in array array[
    'sales_documents','sales_document_lines','sales_document_tax_lines','document_payments',
    'document_credit_allocations','document_ledger_postings','document_etims_submissions',
    'document_delivery_events','invoice_templates','invoice_reminder_rules',
    'recurring_invoice_schedules','customer_contact_preferences','support_access_grants'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from anon',t);
    execute format('revoke insert, update, delete, truncate, references, trigger on public.%I from authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.is_organization_member(organization_id))',
      'Tenant members read '||t,t
    );
  end loop;
end $body$;

-- Support-consent records are more sensitive than ordinary business documents.
drop policy "Tenant members read support_access_grants" on public.support_access_grants;
create policy "Owners and admins read support access grants" on public.support_access_grants
for select to authenticated using (
  exists (
    select 1 from public.organization_members m
    where m.organization_id = support_access_grants.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner','admin')
  )
);

-- Authenticated clients cannot directly mutate the invoice/ledger/support tables.
-- Service-side orchestration and narrow RPCs will be introduced with their own acceptance tests.
