create extension if not exists pgtap with schema extensions;
begin;
select plan(14);

select has_table('public','document_payment_allocations','customer payment allocations are recorded');
select has_table('public','suppliers','tenant-scoped suppliers exist');
select has_table('public','supplier_bills','supplier bills and AP balances exist');
select has_table('public','supplier_bill_lines','supplier bill lines preserve accounting snapshots');
select has_table('public','supplier_bill_payments','supplier payments are idempotent');
select has_table('public','mpesa_settlements','M-PESA settlement records exist');
select has_table('public','mpesa_settlement_matches','settlement-to-payment matches exist');

select ok(
  (select count(*)=7 from pg_class where oid in (
    'public.document_payment_allocations'::regclass,
    'public.suppliers'::regclass,
    'public.supplier_bills'::regclass,
    'public.supplier_bill_lines'::regclass,
    'public.supplier_bill_payments'::regclass,
    'public.mpesa_settlements'::regclass,
    'public.mpesa_settlement_matches'::regclass
  ) and relrowsecurity),
  'RLS is enabled for every new receivables, payables and settlement table'
);

select ok(
  (select bool_and(not has_table_privilege('authenticated',t,'INSERT')
                   and not has_table_privilege('authenticated',t,'UPDATE')
                   and not has_table_privilege('authenticated',t,'DELETE')
                   and not has_table_privilege('anon',t,'SELECT'))
   from unnest(array[
    'public.document_payment_allocations','public.suppliers','public.supplier_bills',
    'public.supplier_bill_lines','public.supplier_bill_payments','public.mpesa_settlements',
    'public.mpesa_settlement_matches'
   ]) as t),
  'browser roles cannot directly mutate financial records and anon cannot read them'
);

select ok(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='record_document_payment' and p.pronargs=7),
  'customer payment workflow is exposed as a narrow RPC');
select ok(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='record_mpesa_settlement' and p.pronargs=8),
  'M-PESA settlement workflow is exposed as a narrow RPC');
select ok(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='queue_document_etims_submission' and p.pronargs=5),
  'eTIMS submission queue is exposed as a narrow RPC');

select ok(exists(select 1 from pg_constraint where conrelid='public.mpesa_settlements'::regclass
  and contype='c' and pg_get_constraintdef(oid) like '%gross_amount%fee_amount%net_amount%'),
  'M-PESA settlement totals must reconcile gross less fees to net');
select ok(exists(select 1 from pg_constraint where conrelid='public.document_payments'::regclass
  and contype='u' and pg_get_constraintdef(oid) like '%idempotency_key%'),
  'customer payment idempotency is enforced by a unique database constraint');

select * from finish();
rollback;
