create extension if not exists pgtap with schema extensions;
begin;
select plan(27);

select has_table('public','sales_documents','one shared sales/invoice/credit-note header exists');
select has_table('public','sales_document_lines','document line snapshots exist');
select has_table('public','sales_document_tax_lines','tax snapshots exist');
select has_table('public','document_payments','document payment state exists');
select has_table('public','document_credit_allocations','credit notes allocate to originals');
select has_table('public','document_ledger_postings','documents link to the existing ledger');
select has_table('public','document_etims_submissions','durable eTIMS submission state exists');
select has_table('public','document_delivery_events','delivery events are tracked separately');
select has_table('public','invoice_templates','tenant invoice templates exist');
select has_table('public','invoice_reminder_rules','tenant reminder rules exist');
select has_table('public','recurring_invoice_schedules','recurring invoice schedule state exists');
select has_table('public','customer_contact_preferences','customer channel consent exists');
select has_table('public','support_access_grants','time-limited support consent records exist');

select ok(
  (select count(*)=13 from pg_class where oid in (
    'public.sales_documents'::regclass,'public.sales_document_lines'::regclass,
    'public.sales_document_tax_lines'::regclass,'public.document_payments'::regclass,
    'public.document_credit_allocations'::regclass,'public.document_ledger_postings'::regclass,
    'public.document_etims_submissions'::regclass,'public.document_delivery_events'::regclass,
    'public.invoice_templates'::regclass,'public.invoice_reminder_rules'::regclass,
    'public.recurring_invoice_schedules'::regclass,'public.customer_contact_preferences'::regclass,
    'public.support_access_grants'::regclass
  ) and relrowsecurity),
  'RLS is enabled on every new document, payment, tax, delivery and support table'
);

select ok(
  (select bool_and(not has_table_privilege('authenticated',t,'INSERT')
                   and not has_table_privilege('authenticated',t,'UPDATE')
                   and not has_table_privilege('authenticated',t,'DELETE')
                   and not has_table_privilege('anon',t,'SELECT'))
   from unnest(array[
    'public.sales_documents','public.sales_document_lines','public.sales_document_tax_lines',
    'public.document_payments','public.document_credit_allocations','public.document_ledger_postings',
    'public.document_etims_submissions','public.document_delivery_events','public.invoice_templates',
    'public.invoice_reminder_rules','public.recurring_invoice_schedules',
    'public.customer_contact_preferences','public.support_access_grants'
   ]) as t),
  'browser roles cannot directly mutate financial records and anon cannot read them'
);

select ok(
  exists(select 1 from pg_policies where schemaname='public' and tablename='support_access_grants'
         and policyname='Owners and admins read support access grants'
         and qual like '%owner%' and qual like '%admin%'),
  'support consent records are visible only to owners and admins'
);

select ok(
  exists(select 1 from pg_constraint where conrelid='public.sales_documents'::regclass
         and conname='sales_documents_organization_id_document_number_key')
  and exists(select 1 from pg_constraint where conrelid='public.sales_documents'::regclass
         and conname='sales_documents_organization_id_legacy_sale_id_key'),
  'document numbers are tenant-unique and legacy sales can be bridged once'
);

create temporary table _document_test_context(organization_id uuid, document_id uuid, credit_id uuid) on commit drop;
do $$
declare
  org_id uuid := gen_random_uuid();
  original_id uuid := gen_random_uuid();
  credit_id uuid := gen_random_uuid();
begin
  insert into public.organizations(id,name,slug) values
    (org_id,'Document Contract Test','doc-test-'||substr(replace(org_id::text,'-',''),1,12));
  insert into public.sales_documents(id,organization_id,document_number,document_type,status,grand_total,amount_paid)
    values(original_id,org_id,'INV-CONTRACT-1','invoice','issued',1000,250);
  insert into public.sales_documents(id,organization_id,document_number,document_type,status,source_document_id,grand_total)
    values(credit_id,org_id,'CN-CONTRACT-1','credit_note','draft',original_id,100);
  insert into _document_test_context values(org_id,original_id,credit_id);
end $$;

select is(
  (select balance_due from public.sales_documents d join _document_test_context c on c.document_id=d.id),
  750::numeric,
  'balance due is generated from document total less stored paid amount'
);

select throws_ok(
  $$insert into public.sales_documents(organization_id,document_number,document_type)
    select organization_id,'INV-CONTRACT-1','invoice' from _document_test_context$$,
  '23505', null, 'duplicate document number in the same tenant is rejected'
);

select throws_ok(
  $$insert into public.sales_documents(organization_id,document_number,document_type)
    select organization_id,'CN-NO-SOURCE','credit_note' from _document_test_context$$,
  '23514', null, 'credit note without an original document is rejected'
);

select ok(
  (select d.document_type='credit_note' and d.source_document_id=c.document_id
   from public.sales_documents d join _document_test_context c on c.credit_id=d.id),
  'credit note explicitly links to its original document'
);

insert into public.document_payments(organization_id,document_id,tender_type,idempotency_key,amount)
  select organization_id,document_id,'mpesa','pay-contract-key',50 from _document_test_context;
select throws_ok(
  $q$insert into public.document_payments(organization_id,document_id,tender_type,idempotency_key,amount)
    select organization_id,document_id,'mpesa','pay-contract-key',50 from _document_test_context$q$,
  '23505', null, 'duplicate payment idempotency key is rejected'
);

select ok(
  exists(select 1 from pg_constraint where conrelid='public.sales_document_lines'::regclass
         and contype='f' and conname='sales_document_lines_organization_id_document_id_fkey')
  and exists(select 1 from pg_constraint where conrelid='public.sales_documents'::regclass
         and contype='f' and conname='sales_documents_organization_id_customer_id_fkey')
  and exists(select 1 from pg_constraint where conrelid='public.sales_documents'::regclass
         and contype='f' and conname='sales_documents_organization_id_legacy_sale_id_fkey'),
  'document and legacy links use tenant-scoped composite foreign keys'
);

select ok(
  exists(select 1 from pg_indexes where schemaname='public' and indexname='document_etims_due_idx')
  and exists(select 1 from pg_indexes where schemaname='public' and indexname='document_delivery_queue_idx')
  and exists(select 1 from pg_indexes where schemaname='public' and indexname='recurring_invoice_due_idx'),
  'retry and scheduled-work queues have supporting partial indexes'
);


insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
  values('33333333-3333-4333-8333-333333333333','authenticated','authenticated','document-rls@example.invalid','',now())
  on conflict (id) do nothing;
insert into public.organizations(id,name,slug) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Document RLS A','doc-rls-a'),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','Document RLS B','doc-rls-b');
insert into public.organization_members(organization_id,user_id,role)
  values('cccccccc-cccc-4ccc-8ccc-cccccccccccc','33333333-3333-4333-8333-333333333333','owner');
insert into public.sales_documents(organization_id,document_number,document_type,status)
  values('cccccccc-cccc-4ccc-8ccc-cccccccccccc','RLS-A-INVOICE','invoice','issued'),
        ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','RLS-B-INVOICE','invoice','issued');

set local role authenticated;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
select is(
  (select count(*)::int from public.sales_documents),
  1,
  'authenticated tenant member sees only their own document'
);
select is(
  (select count(*)::int from public.sales_documents where organization_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
  0,
  'authenticated tenant member cannot read another tenant document'
);
select throws_ok(
  $q$insert into public.sales_documents(organization_id,document_number,document_type)
     values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','RLS-DIRECT-WRITE','invoice')$q$,
  '42501', null, 'authenticated clients cannot directly create financial documents'
);
reset role;

select * from finish();
rollback;
