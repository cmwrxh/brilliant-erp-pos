-- Add a generated tenant_id alias without breaking existing organization_id APIs/FKs.
-- Generated columns cannot drift: tenant_id always equals the canonical organization_id.
alter table public.organizations add column tenant_id uuid generated always as (id) stored;
alter table public.organization_members add column tenant_id uuid generated always as (organization_id) stored;
alter table public.locations add column tenant_id uuid generated always as (organization_id) stored;
alter table public.products add column tenant_id uuid generated always as (organization_id) stored;
alter table public.inventory_balances add column tenant_id uuid generated always as (organization_id) stored;
alter table public.customers add column tenant_id uuid generated always as (organization_id) stored;
alter table public.sales add column tenant_id uuid generated always as (organization_id) stored;
alter table public.sale_items add column tenant_id uuid generated always as (organization_id) stored;
alter table public.sale_payments add column tenant_id uuid generated always as (organization_id) stored;
alter table public.inventory_movements add column tenant_id uuid generated always as (organization_id) stored;
alter table public.payment_provider_accounts add column tenant_id uuid generated always as (organization_id) stored;
alter table public.provider_transactions add column tenant_id uuid generated always as (organization_id) stored;
alter table public.etims_invoices add column tenant_id uuid generated always as (organization_id) stored;
alter table public.mpesa_transactions add column tenant_id uuid generated always as (organization_id) stored;
alter table public.offline_sync_receipts add column tenant_id uuid generated always as (organization_id) stored;

create index organizations_tenant_id_idx on public.organizations(tenant_id);
create index organization_members_tenant_id_idx on public.organization_members(tenant_id);
create index locations_tenant_id_idx on public.locations(tenant_id);
create index products_tenant_id_idx on public.products(tenant_id);
create index inventory_balances_tenant_id_idx on public.inventory_balances(tenant_id);
create index customers_tenant_id_idx on public.customers(tenant_id);
create index sales_tenant_id_idx on public.sales(tenant_id);
create index sale_items_tenant_id_idx on public.sale_items(tenant_id);
create index sale_payments_tenant_id_idx on public.sale_payments(tenant_id);
create index inventory_movements_tenant_id_idx on public.inventory_movements(tenant_id);
create index payment_provider_accounts_tenant_id_idx on public.payment_provider_accounts(tenant_id);
create index provider_transactions_tenant_id_idx on public.provider_transactions(tenant_id);
create index etims_invoices_tenant_id_idx on public.etims_invoices(tenant_id);
create index mpesa_transactions_tenant_id_idx on public.mpesa_transactions(tenant_id);
create index offline_sync_receipts_tenant_id_idx on public.offline_sync_receipts(tenant_id);

-- Restrictive policies AND all existing role/operation policies. A permissive policy
-- elsewhere cannot accidentally widen access across tenant boundaries.
create policy "Tenant boundary tenant_id" on public.organizations as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.organization_members as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.locations as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.products as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.inventory_balances as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.customers as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.sales as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.sale_items as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.sale_payments as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.inventory_movements as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.payment_provider_accounts as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.provider_transactions as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.etims_invoices as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.mpesa_transactions as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));
create policy "Tenant boundary tenant_id" on public.offline_sync_receipts as restrictive for all to authenticated
 using (public.is_organization_member(tenant_id)) with check (public.is_organization_member(tenant_id));

comment on column public.organizations.tenant_id is 'Generated tenant scope alias; equals organizations.id.';
comment on column public.sales.tenant_id is 'Generated tenant scope alias; equals organization_id. Do not write independently.';
