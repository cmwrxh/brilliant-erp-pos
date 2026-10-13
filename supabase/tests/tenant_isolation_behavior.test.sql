create extension if not exists pgtap with schema extensions;
-- Behavioral cross-tenant regression test. All fixtures are rolled back.
begin;
select plan(8);

insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
values
 ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','tenant-a-test@example.invalid','',now()),
 ('22222222-2222-4222-8222-222222222222','authenticated','authenticated','tenant-b-test@example.invalid','',now())
on conflict (id) do nothing;

insert into public.organizations(id,name,slug) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Tenant A Test','tenant-a-isolation-test'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','Tenant B Test','tenant-b-isolation-test')
on conflict (id) do nothing;

insert into public.organization_members(organization_id,user_id,role) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','owner'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222','owner')
on conflict do nothing;

insert into public.products(id,organization_id,sku,name,selling_price) values
 ('aaaaaaaa-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','TENANT-A-ITEM','Tenant A Item',100),
 ('bbbbbbbb-0000-4000-8000-000000000001','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','TENANT-B-ITEM','Tenant B Item',200)
on conflict (id) do nothing;

select ok(has_table_privilege('authenticated','public.products','insert'),
 'authenticated role has insert privilege, so the RLS write test is meaningful');

set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);

select is((select count(*)::int from public.products),1,
 'Tenant A reads only its own product');
select is((select count(*)::int from public.products where organization_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),0,
 'Tenant A cannot directly read Tenant B products');
select throws_ok(
 $$insert into public.products(organization_id,sku,name,selling_price)
   values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','TENANT-A-ATTACK','Cross tenant write',1)$$,
 '42501',null,'Tenant A cannot insert a product into Tenant B');
update public.products set name='Compromised' where id='bbbbbbbb-0000-4000-8000-000000000001';
select is((select count(*)::int from public.products where id='bbbbbbbb-0000-4000-8000-000000000001'),0,
 'Tenant A cannot target Tenant B product in an update');
delete from public.products where id='bbbbbbbb-0000-4000-8000-000000000001';
select is((select count(*)::int from public.products where id='bbbbbbbb-0000-4000-8000-000000000001'),0,
 'Tenant A cannot target Tenant B product in a delete');

reset role;
select is((select count(*)::int from public.products where id='bbbbbbbb-0000-4000-8000-000000000001' and name='Tenant B Item'),1,
 'Tenant B product remains unchanged after Tenant A write attempts');

set local role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
select is((select count(*)::int from public.products),1,
 'Tenant B independently reads its own product');

reset role;
select * from finish();
rollback;
