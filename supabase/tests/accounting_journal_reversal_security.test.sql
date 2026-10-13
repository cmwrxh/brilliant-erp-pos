create extension if not exists pgtap with schema extensions;

begin;
select plan(2);

set local role authenticated;
select set_config('request.jwt.claim.sub','',true);

select throws_ok(
  $$select public.reverse_accounting_journal(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    current_date,
    'unauthenticated attempt'
  )$$,
  '28000',
  'Authentication required.',
  'Journal reversal rejects requests without an authenticated user'
);

select set_config('request.jwt.claim.sub','dddddddd-dddd-4ddd-8ddd-dddddddddddd',true);

select throws_ok(
  $$select public.reverse_accounting_journal(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    current_date,
    'cross tenant attempt'
  )$$,
  '42501',
  'Not authorized to reverse accounting journals.',
  'Journal reversal rejects users who are not members of the requested organization'
);

reset role;
select * from finish();
rollback;
