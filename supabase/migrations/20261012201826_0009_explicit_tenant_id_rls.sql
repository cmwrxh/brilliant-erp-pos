-- Historical tenant_id rollout migration. Migration 0011 tightens these boundary policies to SELECT-only.
-- organization_id remains the established relational key; tenant_id is a generated, non-writable alias.
alter table public.organizations add column if not exists tenant_id uuid generated always as (id) stored;
alter table public.organization_members add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.locations add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.products add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.inventory_balances add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.inventory_movements add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.customers add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.sales add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.sale_items add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.sale_payments add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.payment_provider_accounts add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.provider_transactions add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.etims_invoices add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.mpesa_transactions add column if not exists tenant_id uuid generated always as (organization_id) stored;
alter table public.offline_sync_receipts add column if not exists tenant_id uuid generated always as (organization_id) stored;

do $$
declare t text;
begin
 foreach t in array array[
  'organizations','organization_members','locations','products','inventory_balances',
  'inventory_movements','customers','sales','sale_items','sale_payments',
  'payment_provider_accounts','provider_transactions','etims_invoices','mpesa_transactions','offline_sync_receipts'
 ] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists %I on public.%I','Tenant boundary tenant_id',t);
  execute format('create policy %I on public.%I for all to authenticated using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id))','Tenant boundary tenant_id',t);
 end loop;
end $$;
