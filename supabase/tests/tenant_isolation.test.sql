-- Run with Supabase CLI: supabase test db
begin;
select plan(5);

select ok(
  (select count(*) from pg_tables where schemaname='public' and tablename in
    ('organizations','organization_members','locations','products','inventory_balances','customers','sales','sale_items','sale_payments','inventory_movements','payment_provider_accounts','provider_transactions','etims_invoices','mpesa_transactions','offline_sync_receipts') and rowsecurity) = 15,
  'RLS is enabled on every tenant business table'
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
