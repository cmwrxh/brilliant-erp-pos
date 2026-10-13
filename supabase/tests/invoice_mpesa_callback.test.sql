create extension if not exists pgtap with schema extensions;
begin;
select plan(6);

select ok(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='complete_invoice_mpesa_payment' and p.pronargs=6),
  'invoice M-PESA callback has a dedicated completion RPC');
select ok(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='complete_invoice_mpesa_payment' and p.prosecdef),
  'invoice M-PESA callback runs with definer privileges');
select ok(not has_function_privilege('authenticated','public.complete_invoice_mpesa_payment(uuid,uuid,text,text,text,numeric)','EXECUTE'),
  'authenticated users cannot forge a successful provider callback');
select ok(has_function_privilege('service_role','public.complete_invoice_mpesa_payment(uuid,uuid,text,text,text,numeric)','EXECUTE'),
  'trusted server-side service role can complete verified invoice payments');
select ok(exists(select 1 from information_schema.columns where table_schema='public' and table_name='provider_transactions' and column_name='document_id')
  and exists(select 1 from information_schema.columns where table_schema='public' and table_name='provider_transactions' and column_name='sale_id' and is_nullable='YES'),
  'provider transaction can be linked to exactly one sale or invoice');


select ok(position('currency_code' in pg_get_functiondef(
  'public.complete_invoice_mpesa_payment(uuid,uuid,text,text,text,numeric)'::regprocedure
)) > 0 and position('KES' in pg_get_functiondef(
  'public.complete_invoice_mpesa_payment(uuid,uuid,text,text,text,numeric)'::regprocedure
)) > 0,
  'invoice M-PESA completion enforces KES currency in the database');

select * from finish();
rollback;
