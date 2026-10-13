-- Compliance and resilient-sync foundations. No provider is considered live by this migration.
-- Existing organization_id is the canonical tenant key; keep it consistent with all composite FKs.
alter table public.sales
  add column if not exists buyer_pin text,
  add column if not exists offline_client_id uuid,
  add column if not exists tax_invoice_status text not null default 'not_requested'
    check (tax_invoice_status in ('not_requested','queued','submitted','accepted','rejected','requires_review')),
  add column if not exists tax_invoice_reference text,
  add column if not exists tax_invoice_error text;
alter table public.sales add constraint sales_buyer_pin_format_check
  check (buyer_pin is null or buyer_pin ~ '^[A-Z0-9]{11}$');
create unique index if not exists sales_org_offline_client_id_uidx
  on public.sales(organization_id,offline_client_id) where offline_client_id is not null;

create table public.etims_invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  sale_id uuid not null,
  invoice_kind text not null default 'invoice' check (invoice_kind in ('invoice','credit_note','reversal')),
  original_invoice_id uuid,
  status text not null default 'queued' check (status in ('queued','submitting','accepted','rejected','retryable_error','requires_review')),
  buyer_pin text check (buyer_pin is null or buyer_pin ~ '^[A-Z0-9]{11}$'),
  internal_reference text not null,
  control_unit_invoice_number text,
  control_unit_receipt_number text,
  signature text,
  request_payload jsonb not null default '{}'::jsonb,
  response_payload jsonb not null default '{}'::jsonb,
  error_code text,
  error_message text,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  next_attempt_at timestamptz,
  submitted_at timestamptz,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,internal_reference),
  foreign key (organization_id,sale_id) references public.sales(organization_id,id) on delete restrict,
  foreign key (organization_id,original_invoice_id) references public.etims_invoices(organization_id,id) on delete restrict,
  check ((invoice_kind='invoice' and original_invoice_id is null) or (invoice_kind in ('credit_note','reversal') and original_invoice_id is not null))
);
create unique index etims_one_invoice_per_sale_kind on public.etims_invoices(organization_id,sale_id,invoice_kind) where invoice_kind='invoice';
create index etims_retry_queue_idx on public.etims_invoices(status,next_attempt_at) where status in ('queued','retryable_error');
create index etims_org_created_idx on public.etims_invoices(organization_id,created_at desc);
alter table public.etims_invoices enable row level security;
create policy "Members read eTIMS invoices" on public.etims_invoices for select to authenticated using (public.is_organization_member(organization_id));
revoke all on public.etims_invoices from anon,authenticated;

-- Store Till/Paybill collection events separately from the mutable payment-matching result.
-- A unique provider receipt prevents duplicate webhook delivery from creating duplicate money.
create table public.mpesa_transactions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  provider_receipt text not null,
  transaction_type text not null default 'c2b' check (transaction_type in ('c2b','stk_push','reversal')),
  shortcode text,
  account_reference text,
  phone_number text,
  amount numeric(14,2) not null check (amount > 0),
  currency_code char(3) not null default 'KES',
  transaction_time timestamptz,
  checkout_request_id text,
  merchant_request_id text,
  result_code text,
  result_description text,
  matched_sale_id uuid,
  matching_status text not null default 'unmatched' check (matching_status in ('unmatched','matched','ambiguous','ignored','reversed')),
  matched_at timestamptz,
  raw_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,provider_receipt),
  foreign key (organization_id,matched_sale_id) references public.sales(organization_id,id) on delete restrict
);
create unique index mpesa_checkout_request_uidx on public.mpesa_transactions(organization_id,checkout_request_id) where checkout_request_id is not null;
create index mpesa_unmatched_idx on public.mpesa_transactions(organization_id,transaction_time desc) where matching_status='unmatched';
create index mpesa_receipt_match_idx on public.mpesa_transactions(organization_id,account_reference,amount,transaction_time);
alter table public.mpesa_transactions enable row level security;
create policy "Members read M-PESA transactions" on public.mpesa_transactions for select to authenticated using (public.is_organization_member(organization_id));
revoke all on public.mpesa_transactions from anon,authenticated;

-- Every retryable offline submission has a stable client-generated UUID and server-side outcome.
create table public.offline_sync_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  client_operation_id uuid not null,
  operation_type text not null check (operation_type in ('sale','stock_receipt','customer')),
  status text not null default 'received' check (status in ('received','processing','synced','rejected','requires_review')),
  result_record_id uuid,
  payload_hash text not null check (payload_hash ~ '^[a-f0-9]{64}$'),
  error_code text,
  error_message text,
  received_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (organization_id,client_operation_id)
);
create index offline_sync_pending_idx on public.offline_sync_receipts(organization_id,received_at) where status in ('received','processing','requires_review');
alter table public.offline_sync_receipts enable row level security;
create policy "Members read offline sync receipts" on public.offline_sync_receipts for select to authenticated using (public.is_organization_member(organization_id));
revoke all on public.offline_sync_receipts from anon,authenticated;

comment on column public.sales.organization_id is 'Canonical tenant key for this shared multi-business schema; application-facing tenant_id terminology maps to this column.';
comment on table public.etims_invoices is 'Durable eTIMS outbox and audit trail. Transmission requires taxpayer-specific KRA OSCU/VSCU onboarding, credentials and certification.';
comment on table public.mpesa_transactions is 'Idempotent M-PESA STK/C2B/Till/Paybill events; unmatched payments must never be guessed into a sale.';
comment on table public.offline_sync_receipts is 'Idempotency ledger for offline client operations; same operation ID and same payload can safely be retried.';
