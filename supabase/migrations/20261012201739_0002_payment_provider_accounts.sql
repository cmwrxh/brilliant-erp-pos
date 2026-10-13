-- Provider secrets are encrypted by the application before insertion.
-- No RLS policies are intentionally defined for this table: browsers cannot read or write credentials.
create table public.payment_provider_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null check (provider in ('mpesa','airtel_money','flutterwave','paystack')),
  encrypted_credentials text not null,
  enabled boolean not null default false,
  last_four_hint text,
  environment text not null default 'test' check (environment in ('test','live')),
  configured_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, provider)
);
alter table public.payment_provider_accounts enable row level security;
revoke all on public.payment_provider_accounts from anon, authenticated;

create table public.provider_transactions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  sale_id uuid not null,
  provider text not null check (provider in ('mpesa','airtel_money','flutterwave','paystack')),
  reference text not null unique,
  provider_reference text,
  amount numeric(14,2) not null check (amount > 0),
  currency_code char(3) not null default 'KES',
  status text not null default 'pending' check (status in ('pending','succeeded','failed','cancelled','reversed')),
  provider_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, sale_id) references public.sales(organization_id, id)
);
create index provider_transactions_org_created_idx on public.provider_transactions(organization_id, created_at desc);
create index provider_transactions_sale_idx on public.provider_transactions(organization_id, sale_id);
alter table public.provider_transactions enable row level security;
create policy "Members read provider transactions" on public.provider_transactions for select to authenticated using (public.is_organization_member(organization_id));
-- Only trusted server-side code (service role) may insert or change transaction status.
revoke insert, update, delete on public.provider_transactions from anon, authenticated;

comment on table public.payment_provider_accounts is 'Encrypted tenant payment-provider credentials. Accessible only to trusted server-side service-role code.';
comment on column public.payment_provider_accounts.encrypted_credentials is 'AES-256-GCM ciphertext from application code; never expose through the Data API.';
