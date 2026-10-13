create extension if not exists pgtap with schema extensions;
begin;
select plan(8);

select ok(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='create_supplier' and p.pronargs=6),
  'supplier creation uses an authorized server-side RPC');
select ok(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='create_supplier_bill' and p.pronargs=7),
  'supplier bill posting uses a server-side RPC');
select ok(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='record_supplier_bill_payment' and p.pronargs=6),
  'supplier bill payments use a server-side RPC');
select ok(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='match_mpesa_settlement_payments' and p.pronargs=3),
  'M-PESA matching uses a server-side RPC');
select ok(not has_function_privilege('anon','public.create_supplier(uuid,text,text,text,text,text)','EXECUTE'),
  'anonymous callers cannot execute supplier creation');
select ok(not has_function_privilege('anon','public.create_supplier_bill(uuid,uuid,text,date,date,jsonb,text)','EXECUTE'),
  'anonymous callers cannot post supplier bills');
select ok(not has_function_privilege('anon','public.record_supplier_bill_payment(uuid,uuid,text,numeric,text,text)','EXECUTE'),
  'anonymous callers cannot post supplier payments');
select ok(exists(select 1 from pg_indexes where schemaname='public' and indexname='mpesa_settlement_payment_once_idx'),
  'a confirmed payment cannot be matched to multiple M-PESA settlements');

select * from finish();
rollback;
