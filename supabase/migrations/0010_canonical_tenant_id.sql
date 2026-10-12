-- Repair the existing tenant boundary columns without dropping policies that depend on them.
-- organization_id remains the established FK key; CHECK constraints prevent tenant drift.
do $$
declare t text;
begin
  foreach t in array array[
    'customers','etims_invoices','inventory_balances','inventory_movements',
    'locations','mpesa_transactions','organization_members','payment_provider_accounts',
    'products','provider_transactions','sale_items','sale_payments','sales',
    'offline_sync_receipts'
  ] loop
    execute format('update public.%I set tenant_id = organization_id where tenant_id is distinct from organization_id', t);
    execute format('alter table public.%I alter column tenant_id set not null', t);
    execute format('alter table public.%I drop constraint if exists %I', t, t || '_tenant_matches_organization');
    execute format('alter table public.%I add constraint %I check (tenant_id = organization_id)', t, t || '_tenant_matches_organization');
  end loop;
end $$;
update public.organizations set tenant_id=id where tenant_id is distinct from id;
alter table public.organizations alter column tenant_id set not null;
alter table public.organizations drop constraint if exists organizations_tenant_matches_id;
alter table public.organizations add constraint organizations_tenant_matches_id check (tenant_id=id);

revoke all on public.organizations, public.organization_members, public.locations,
  public.products, public.inventory_balances, public.inventory_movements,
  public.customers, public.sales, public.sale_items, public.sale_payments,
  public.payment_provider_accounts, public.provider_transactions,
  public.etims_invoices, public.mpesa_transactions, public.offline_sync_receipts
from anon;

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
comment on column public.organizations.tenant_id is 'Non-null, constrained to organization id; canonical tenant boundary.';
