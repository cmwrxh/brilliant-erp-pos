create extension if not exists pgtap with schema extensions;
begin;
select plan(5);

select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.journal_entries'::regclass
      and tgname = 'journal_entries_period_write_guard'
      and not tgisinternal
  ),
  'journal writes are guarded by accounting-period locks'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.sales'::regclass
      and tgname = 'post_completed_sale_to_ledger_after_completion'
      and not tgisinternal
  )
  and exists (
    select 1 from pg_trigger
    where tgrelid = 'public.sales'::regclass
      and tgname = 'enqueue_completed_sale_for_etims_after_completion'
      and not tgisinternal
  ),
  'ledger posting and eTIMS enqueue are database triggers on sale completion'
);

select ok(
  position('for update' in lower(pg_get_functiondef('public.close_accounting_period(uuid,uuid,text)'::regprocedure))) > 0,
  'period close serializes on the organization accounting lock'
);

select ok(
  position('insufficient stock to complete sale' in lower(pg_get_functiondef('public.complete_sale(uuid,uuid,text,numeric,text)'::regprocedure))) > 0
  and position('for update' in lower(pg_get_functiondef('public.complete_sale(uuid,uuid,text,numeric,text)'::regprocedure))) > 0,
  'checkout locks stock balances and rejects quantities above available stock'
);

do $$
declare
  org_id uuid := gen_random_uuid();
  period_id uuid := gen_random_uuid();
begin
  insert into public.organizations(id,name,slug)
  values(org_id,'Period Lock Guard Test','period-lock-'||substr(replace(org_id::text,'-',''),1,12));

  insert into public.accounting_periods(
    id,organization_id,period_name,starts_on,ends_on,status,closed_at
  ) values (
    period_id,org_id,'Closed test period',date '2026-01-01',date '2026-01-31','closed',now()
  );
end $$;

select throws_ok(
  format(
    'insert into public.journal_entries(organization_id,journal_number,accounting_date,description,source_type,source_id,posting_purpose,status) values (%L, 990001, date %L, %L, %L, %L, %L, %L)',
    (select id::text from public.organizations where slug like 'period-lock-%' order by created_at desc limit 1),
    '2026-01-15',
    'Closed-period guard test',
    'test',
    gen_random_uuid(),
    'period-lock-test',
    'draft'
  ),
  '23514',
  'Accounting period is closed; posted transactions cannot be written into it.',
  'journal insertion into a closed accounting period is rejected'
);

select * from finish();
rollback;
