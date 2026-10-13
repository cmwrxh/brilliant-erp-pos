create extension if not exists pgtap with schema extensions;
begin;
select plan(5);
create temporary table _release_gate_org(id uuid) on commit drop;
do $$
declare org_id uuid := gen_random_uuid();
begin
  insert into public.organizations(id,name,slug)
  values(org_id,'Workflow Gate Test','gate-test-'||substr(replace(org_id::text,'-',''),1,12));
  insert into _release_gate_org values(org_id);
end $$;

select ok(exists(select 1 from information_schema.columns where table_schema='public' and table_name='accounting_settings'
  and column_name='invoice_workflows_enabled' and column_default='false')
  and exists(select 1 from information_schema.columns where table_schema='public' and table_name='accounting_settings'
  and column_name='accounting_workflows_enabled' and column_default='false'),
  'invoice and accounting workflows are disabled by default at the database level');

select throws_ok(
  $$insert into public.sales_documents(organization_id,document_number,document_type)
    select id,'INV-GATED-1','invoice' from _release_gate_org$$,
  '55000', null, 'invoice RPCs cannot bypass the database release gate');

select throws_ok(
  $$insert into public.suppliers(organization_id,name)
    select id,'Gated supplier' from _release_gate_org$$,
  '55000', null, 'supplier/AP workflows cannot bypass the database release gate');

select ok(not has_table_privilege('authenticated','public.accounting_settings','UPDATE'),
  'authenticated browser clients cannot switch database release gates');

select ok(exists(select 1 from pg_trigger where tgname='gate_provider_transactions_invoice' and not tgisinternal),
  'invoice M-PESA initiation is protected by a database trigger');

select * from finish();
rollback;
