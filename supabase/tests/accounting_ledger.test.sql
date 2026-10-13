create extension if not exists pgtap with schema extensions;
-- Run against a disposable Supabase database after migration 0014.
begin;
select plan(10);

select has_table('public','accounting_settings','accounting settings table exists');
select has_table('public','chart_of_accounts','tenant chart of accounts exists');
select has_table('public','journal_entries','journal header table exists');
select has_table('public','journal_lines','journal line table exists');
select has_table('public','accounting_periods','accounting periods table exists');
select has_table('public','accounting_audit_log','accounting audit log exists');

select ok(
  (select count(*) from pg_class where oid in (
    'public.accounting_settings'::regclass,'public.chart_of_accounts'::regclass,
    'public.accounting_periods'::regclass,'public.journal_entries'::regclass,
    'public.journal_lines'::regclass,'public.accounting_audit_log'::regclass
  ) and relrowsecurity) = 6,
  'RLS is enabled on all accounting tables'
);

select ok(
  has_function_privilege('authenticated','public.post_accounting_journal(uuid,date,text,text,uuid,text,jsonb,uuid)','execute')
  and not has_table_privilege('authenticated','public.journal_entries','insert')
  and not has_table_privilege('authenticated','public.journal_lines','insert')
  and not has_table_privilege('anon','public.journal_entries','select'),
  'posting is exposed through a function and clients cannot directly write journal rows'
);

do $$
declare
  org_id uuid := gen_random_uuid();
  acct_debit uuid := gen_random_uuid();
  acct_credit uuid := gen_random_uuid();
  journal_id uuid := gen_random_uuid();
begin
  insert into public.organizations(id,name,slug) values(org_id,'Accounting Test','acct-test-'||substr(replace(org_id::text,'-',''),1,12));
  insert into public.accounting_settings(organization_id) values(org_id);
  insert into public.chart_of_accounts(id,organization_id,code,name,account_type,normal_balance)
    values(acct_debit,org_id,'TEST100','Test debit account','asset','debit'),
          (acct_credit,org_id,'TEST400','Test credit account','revenue','credit');
  insert into public.journal_entries(id,organization_id,journal_number,accounting_date,description,source_type,source_id,posting_purpose,status)
    values(journal_id,org_id,1,current_date,'Deliberately unbalanced test','test',gen_random_uuid(),'unbalanced','draft');
  insert into public.journal_lines(organization_id,journal_entry_id,line_number,account_id,debit,credit)
    values(org_id,journal_id,1,acct_debit,100,0),(org_id,journal_id,2,acct_credit,0,90);
  begin
    update public.journal_entries set status='posted',posted_at=now() where id=journal_id;
    raise exception 'TEST FAILED: unbalanced journal was accepted';
  exception when check_violation then
    if sqlerrm not like 'Journal must contain at least two lines and equal debit/credit totals.%' then raise; end if;
  end;
end $$;
select ok(true,'database rejects an unbalanced journal at posting time');

do $$
declare
  org_id uuid := gen_random_uuid();
  acct_debit uuid := gen_random_uuid();
  acct_credit uuid := gen_random_uuid();
  journal_id uuid := gen_random_uuid();
begin
  insert into public.organizations(id,name,slug) values(org_id,'Immutable Test','immut-test-'||substr(replace(org_id::text,'-',''),1,12));
  insert into public.accounting_settings(organization_id) values(org_id);
  insert into public.chart_of_accounts(id,organization_id,code,name,account_type,normal_balance)
    values(acct_debit,org_id,'TEST110','Test cash','asset','debit'),
          (acct_credit,org_id,'TEST410','Test income','revenue','credit');
  insert into public.journal_entries(id,organization_id,journal_number,accounting_date,description,source_type,source_id,posting_purpose,status)
    values(journal_id,org_id,1,current_date,'Balanced test journal','test',gen_random_uuid(),'immutable','draft');
  insert into public.journal_lines(organization_id,journal_entry_id,line_number,account_id,debit,credit)
    values(org_id,journal_id,1,acct_debit,100,0),(org_id,journal_id,2,acct_credit,0,100);
  update public.journal_entries set status='posted',posted_at=now() where id=journal_id;
  begin
    update public.journal_entries set description='Tampered' where id=journal_id;
    raise exception 'TEST FAILED: posted journal was mutable';
  exception when sqlstate '55000' then
    if sqlerrm <> 'Posted journal history is immutable; create a reversal.' then raise; end if;
  end;
  begin
    update public.journal_lines set debit=99 where journal_entry_id=journal_id and line_number=1;
    raise exception 'TEST FAILED: posted journal line was mutable';
  exception when sqlstate '55000' then
    if sqlerrm <> 'Posted journal lines are immutable; create a reversal.' then raise; end if;
  end;
end $$;
select ok(true,'posted journal headers and lines are immutable');

select * from finish();
rollback;
