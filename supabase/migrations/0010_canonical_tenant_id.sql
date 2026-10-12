-- Make tenant_id a non-writable alias of the existing canonical tenant key.
-- This avoids allowing organization_id and tenant_id to diverge.
do $$
declare t text;
begin
  foreach t in array array[
    'customers','etims_invoices','inventory_balances','inventory_movements',
    'locations','mpesa_transactions','organization_members','payment_provider_accounts',
    'products','provider_transactions','sale_items','sale_payments','sales',
    'offline_sync_receipts'
  ] loop
    execute format('alter table public.%I drop column if exists tenant_id', t);
    execute format('alter table public.%I add column tenant_id uuid generated always as (organization_id) stored', t);
  end loop;
  alter table public.organizations drop column if exists tenant_id;
  alter table public.organizations add column tenant_id uuid generated always as (id) stored;
end $$;

-- Revoke broad default privileges from the anonymous role for all tenant data.
revoke all on public.organizations, public.organization_members, public.locations,
  public.products, public.inventory_balances, public.inventory_movements,
  public.customers, public.sales, public.sale_items, public.sale_payments,
  public.payment_provider_accounts, public.provider_transactions,
  public.etims_invoices, public.mpesa_transactions, public.offline_sync_receipts
from anon;

-- Keep tenant-scoped business tables under RLS and assert it explicitly.
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.locations enable row level security;
alter table public.products enable row level security;
alter table public.inventory_balances enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.customers enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.sale_payments enable row level security;
alter table public.payment_provider_accounts enable row level security;
alter table public.provider_transactions enable row level security;
alter table public.etims_invoices enable row level security;
alter table public.mpesa_transactions enable row level security;
alter table public.offline_sync_receipts enable row level security;

comment on column public.organizations.tenant_id is 'Generated tenant identifier equal to the organization ID; never client-writable.';
