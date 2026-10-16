create extension if not exists pgtap with schema extensions;
begin;
select plan(9);

-- Deterministic tenant/user fixtures. Organization creation seeds the accounting chart/settings.
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
values
 ('77777777-7777-4777-8777-777777777777','authenticated','authenticated','integrity-owner@example.invalid','',now())
on conflict (id) do nothing;

insert into public.organizations(id,name,slug)
values ('77777777-0000-4777-8777-777777777777','Transaction Integrity Test','transaction-integrity-test')
on conflict (id) do nothing;

insert into public.organization_members(organization_id,user_id,role)
values ('77777777-0000-4777-8777-777777777777','77777777-7777-4777-8777-777777777777','owner')
on conflict do nothing;

insert into public.locations(id,organization_id,name,code)
values ('77777777-0000-4777-8777-000000000001','77777777-0000-4777-8777-777777777777','Integrity Test Branch','MAIN')
on conflict (id) do nothing;

insert into public.products(id,organization_id,sku,name,unit,cost_price,selling_price,tax_rate,is_active)
values ('77777777-0000-4777-8777-000000000002','77777777-0000-4777-8777-777777777777','INTEGRITY-ITEM','Integrity Test Item','each',100,500,0,true)
on conflict (id) do nothing;

insert into public.inventory_balances(organization_id,location_id,product_id,quantity,reorder_level)
values ('77777777-0000-4777-8777-777777777777','77777777-0000-4777-8777-000000000001','77777777-0000-4777-8777-000000000002',5,0)
on conflict (location_id,product_id) do update set quantity=5;

insert into public.inventory_valuation_balances(organization_id,location_id,product_id,quantity,carrying_value,average_unit_cost)
values ('77777777-0000-4777-8777-777777777777','77777777-0000-4777-8777-000000000001','77777777-0000-4777-8777-000000000002',5,500,100)
on conflict (location_id,product_id) do update
set quantity=5,carrying_value=500,average_unit_cost=100;

-- A failure injected after both completion triggers have run must roll back the whole checkout.
create or replace function public.test_fail_after_checkout_side_effects()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if NEW.status = 'completed' and OLD.status is distinct from 'completed' then
    raise exception 'intentional eTIMS-stage failure for atomic rollback test' using errcode = 'P0001';
  end if;
  return NEW;
end;
$$;
create trigger zz_test_fail_after_checkout_side_effects
after update of status on public.sales
for each row execute function public.test_fail_after_checkout_side_effects();

set local role authenticated;
select set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);

select throws_ok(
  $$select public.checkout_sale(
    '77777777-0000-4777-8777-777777777777',
    '77777777-0000-4777-8777-000000000001',
    '[{"product_id":"77777777-0000-4777-8777-000000000002","quantity":1,"discount_amount":0}]'::jsonb,
    null
  )$$,
  'P0001',
  'intentional eTIMS-stage failure for atomic rollback test',
  'forced downstream failure aborts checkout'
);

reset role;
select is(
  (select count(*)::int from public.sales where organization_id='77777777-0000-4777-8777-777777777777'),
  0,
  'sale row rolls back after forced post-trigger failure'
);
select is(
  (select count(*)::int from public.journal_entries where organization_id='77777777-0000-4777-8777-777777777777' and source_type='sale'),
  0,
  'general-ledger sale journals roll back after forced post-trigger failure'
);
select is(
  (select count(*)::int from public.kra_etims_outbox where organization_id='77777777-0000-4777-8777-777777777777'),
  0,
  'eTIMS outbox snapshot rolls back after forced post-trigger failure'
);
select is(
  (select quantity from public.inventory_balances where organization_id='77777777-0000-4777-8777-777777777777' and location_id='77777777-0000-4777-8777-000000000001' and product_id='77777777-0000-4777-8777-000000000002'),
  5::numeric,
  'stock balance rolls back after forced post-trigger failure'
);

-- Drop the fault injector, then prove a quantity above both stock balances is rejected.
drop trigger zz_test_fail_after_checkout_side_effects on public.sales;
drop function public.test_fail_after_checkout_side_effects();

set local role authenticated;
select set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
select throws_ok(
  $$select public.checkout_sale(
    '77777777-0000-4777-8777-777777777777',
    '77777777-0000-4777-8777-000000000001',
    '[{"product_id":"77777777-0000-4777-8777-000000000002","quantity":6,"discount_amount":0}]'::jsonb,
    null
  )$$,
  '23514',
  'Insufficient stock to complete sale',
  'sale quantity above available stock is rejected before completion'
);
reset role;

-- Verify the database trigger itself rejects retroactive journal writes into a closed period.
insert into public.accounting_periods(id,organization_id,period_name,starts_on,ends_on,status,closed_at)
values ('77777777-0000-4777-8777-000000000003','77777777-0000-4777-8777-777777777777','Closed test period',date '2026-01-01',date '2026-01-31','closed',now())
on conflict (id) do nothing;

select throws_ok(
  format(
    'insert into public.journal_entries(organization_id,journal_number,accounting_date,description,source_type,source_id,posting_purpose,status) values (%L, 990001, date %L, %L, %L, %L, %L, %L)',
    '77777777-0000-4777-8777-777777777777',
    '2026-01-15',
    'Closed-period guard test',
    'test',
    '77777777-0000-4777-8777-000000000004',
    'period-lock-test',
    'draft'
  ),
  '23514',
  'Accounting period is closed; posted transactions cannot be written into it.',
  'journal insertion dated in a closed period is rejected by the trigger'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.journal_entries'::regclass
      and tgname = 'journal_entries_period_write_guard'
      and not tgisinternal
  )
  and exists (
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
  'period guard, ledger posting and eTIMS queue triggers are installed'
);

select * from finish();
rollback;
