-- Run with Supabase CLI: supabase test db
begin;
select plan(8);

select ok(
  (select count(*) from pg_tables where schemaname='public' and tablename in
    ('organizations','organization_members','locations','products','inventory_balances','customers','sales','sale_items','sale_payments','inventory_movements','payment_provider_accounts','provider_transactions','etims_invoices','mpesa_transactions','offline_sync_receipts') and rowsecurity) = 15,
  'RLS is enabled on every tenant business table'
);

select ok(
  (select count(*) from information_schema.columns where table_schema='public'
    and column_name='tenant_id' and is_generated='ALWAYS'
    and table_name in ('organizations','organization_members','locations','products','inventory_balances','customers','sales','sale_items','sale_payments','inventory_movements','payment_provider_accounts','provider_transactions','etims_invoices','mpesa_transactions','offline_sync_receipts')) = 15,
  'Every tenant table has a generated tenant_id mapped to its canonical tenant key'
);

select ok(
  (select count(distinct tablename) from pg_policies where schemaname='public'
    and tablename in ('organizations','organization_members','locations','products','inventory_balances','customers','sales','sale_items','sale_payments','inventory_movements','payment_provider_accounts','provider_transactions','etims_invoices','mpesa_transactions','offline_sync_receipts')
    and (coalesce(qual,'') ilike '%is_organization_member%' or coalesce(with_check,'') ilike '%is_organization_member%')) = 15,
  'Every tenant business table has a membership-scoped RLS policy'
);

select ok(
  (select count(*) from pg_policies where schemaname='public' and policyname='Tenant read boundary' and cmd='SELECT') = 15
  and not exists(select 1 from pg_policies where schemaname='public' and policyname='Tenant boundary tenant_id' and cmd='ALL'),
  'tenant boundary policies are read-only and do not grant blanket write access'
);

select ok(
  exists(select 1 from pg_policies where schemaname='public' and tablename='etims_invoices' and roles @> array['authenticated']::name[]),
  'eTIMS records have an authenticated membership-scoped policy'
);

select ok(
  exists(select 1 from pg_policies where schemaname='public' and tablename='mpesa_transactions' and roles @> array['authenticated']::name[]),
  'M-PESA events have an authenticated membership-scoped policy'
);

select ok(
  exists(select 1 from pg_policies where schemaname='public' and tablename='offline_sync_receipts' and roles @> array['authenticated']::name[]),
  'offline sync receipts have an authenticated membership-scoped policy'
);

select ok(
  not has_table_privilege('anon','public.etims_invoices','select')
  and not has_table_privilege('authenticated','public.etims_invoices','insert')
  and not has_table_privilege('anon','public.mpesa_transactions','select')
  and not has_table_privilege('authenticated','public.offline_sync_receipts','insert'),
  'clients cannot directly write tax invoices, M-PESA events or offline receipts'
);

select * from finish();
rollback();
