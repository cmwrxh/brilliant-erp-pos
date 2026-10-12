-- Database invariants supporting M-PESA webhook idempotency and tenant-scoped secrets.
begin;
select plan(5);

select ok(
  exists(select 1 from pg_indexes where schemaname='public' and tablename='mpesa_transactions'
    and indexdef ilike '%unique%' and indexdef ilike '%organization_id%' and indexdef ilike '%provider_receipt%'),
  'M-PESA receipt is unique within each tenant'
);

select ok(
  exists(select 1 from pg_indexes where schemaname='public' and tablename='mpesa_transactions'
    and indexdef ilike '%checkout_request_id%' and indexdef ilike '%unique%'),
  'M-PESA checkout request IDs have a uniqueness guard'
);

select ok(
  exists(select 1 from information_schema.columns where table_schema='public'
    and table_name='provider_transactions' and column_name='callback_token_hash')
  and exists(select 1 from information_schema.columns where table_schema='public'
    and table_name='payment_provider_accounts' and column_name='c2b_callback_token_hash'),
  'STK and C2B callback tokens are persisted as hashes, not raw tokens'
);

select ok(
  exists(select 1 from pg_constraint where conrelid='public.sale_payments'::regclass
    and contype='c' and pg_get_constraintdef(oid) ilike '%mpesa%'),
  'Sale payment method constraint accepts M-PESA payments'
);

select ok(
  (select relrowsecurity from pg_class where oid='public.mpesa_transactions'::regclass)
  and (select relrowsecurity from pg_class where oid='public.provider_transactions'::regclass)
  and (select relrowsecurity from pg_class where oid='public.payment_provider_accounts'::regclass),
  'M-PESA ledger, provider transactions and encrypted credentials are protected by RLS'
);

select * from finish();
rollback;
