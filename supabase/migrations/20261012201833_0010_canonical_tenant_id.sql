-- Verify and preserve the canonical tenant columns introduced by migration 0009.
-- tenant_id is generated from organization_id (or id for organizations), so it cannot drift.
do $$
declare t text;
begin
  foreach t in array array[
    'customers','etims_invoices','inventory_balances','inventory_movements',
    'locations','mpesa_transactions','organization_members','payment_provider_accounts',
    'products','provider_transactions','sale_items','sale_payments','sales',
    'offline_sync_receipts'
  ] loop
    if not exists (
      select 1 from information_schema.columns c
      where c.table_schema='public' and c.table_name=t and c.column_name='tenant_id'
        and c.is_generated='ALWAYS'
    ) then
      raise exception 'Expected generated tenant_id on public.%',t;
    end if;
  end loop;
  if not exists (
    select 1 from information_schema.columns c
    where c.table_schema='public' and c.table_name='organizations'
      and c.column_name='tenant_id' and c.is_generated='ALWAYS'
  ) then raise exception 'Expected generated tenant_id on public.organizations'; end if;
end $$;

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
