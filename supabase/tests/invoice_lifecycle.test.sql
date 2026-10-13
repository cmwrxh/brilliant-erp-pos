create extension if not exists pgtap with schema extensions;
begin;
select plan(6);

select ok(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='create_sales_invoice_draft' and p.pronargs=7),
  'invoice draft creation is exposed through a narrow RPC');
select ok(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='issue_sales_invoice' and p.pronargs=2),
  'invoice issue posts through a narrow RPC');
select ok(not has_function_privilege('anon','public.create_sales_invoice_draft(uuid,text,uuid,uuid,timestamptz,jsonb,text)','EXECUTE'),
  'anonymous callers cannot create invoice drafts');
select ok(not has_function_privilege('anon','public.issue_sales_invoice(uuid,uuid)','EXECUTE'),
  'anonymous callers cannot issue invoices');
select ok(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='issue_sales_invoice' and prosecdef
    and coalesce(array_to_string(p.proconfig,','),'') like '%search_path=""%'),
  'invoice posting RPC uses a fixed empty search_path');
select ok(exists(select 1 from pg_constraint where conrelid='public.sales_documents'::regclass
  and conname='sales_documents_organization_id_id_key'),
  'invoice IDs are tenant-scoped for composite foreign keys');

select * from finish();
rollback;
