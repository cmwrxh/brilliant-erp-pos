-- Tenant-boundary policies must not grant broad writes by being permissive FOR ALL policies.
-- Writes are granted only by table-specific role policies or trusted SECURITY DEFINER RPCs.
do $$
declare t text;
begin
  foreach t in array array[
    'customers','etims_invoices','inventory_balances','inventory_movements',
    'locations','mpesa_transactions','offline_sync_receipts','organization_members',
    'organizations','payment_provider_accounts','products','provider_transactions',
    'sale_items','sale_payments','sales'
  ] loop
    execute format('drop policy if exists %I on public.%I','Tenant boundary tenant_id',t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.is_organization_member(tenant_id))',
      'Tenant read boundary',t
    );
  end loop;
end $$;

-- Defense in depth: anon must not be able to use tenant business tables.
revoke all on public.organizations, public.organization_members, public.locations,
  public.products, public.inventory_balances, public.inventory_movements,
  public.customers, public.sales, public.sale_items, public.sale_payments,
  public.payment_provider_accounts, public.provider_transactions,
  public.etims_invoices, public.mpesa_transactions, public.offline_sync_receipts
from anon;
