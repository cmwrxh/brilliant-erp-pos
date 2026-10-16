create extension if not exists pgtap with schema extensions;
begin;
select plan(15);

insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
values ('88888888-8888-4888-8888-888888888888','authenticated','authenticated','sprint2-owner@example.invalid','',now())
on conflict (id) do nothing;
insert into public.organizations(id,name,slug)
values ('88888888-0000-4888-8888-000000000000','Sprint 2 Engine Test','sprint2-engine-test')
on conflict (id) do nothing;
insert into public.organization_members(organization_id,user_id,role)
values ('88888888-0000-4888-8888-000000000000','88888888-8888-4888-8888-888888888888','owner')
on conflict do nothing;
insert into public.locations(id,organization_id,name,code)
values ('88888888-0000-4888-8888-000000000001','88888888-0000-4888-8888-000000000000','Manufacturing Test','MFG')
on conflict (id) do nothing;
insert into public.products(id,organization_id,sku,name,unit,cost_price,selling_price,tax_rate,is_active)
values
 ('88888888-0000-4888-8888-000000000002','88888888-0000-4888-8888-000000000000','RAW-TEST','Raw component','each',50,80,0,true),
 ('88888888-0000-4888-8888-000000000003','88888888-0000-4888-8888-000000000000','FIN-TEST','Finished product','each',0,150,0,true)
on conflict (id) do nothing;
update public.accounting_settings set accounting_workflows_enabled=true
where organization_id='88888888-0000-4888-8888-000000000000';

insert into public.inventory_balances(organization_id,location_id,product_id,quantity,reorder_level)
values ('88888888-0000-4888-8888-000000000000','88888888-0000-4888-8888-000000000001','88888888-0000-4888-8888-000000000002',10,0)
on conflict (location_id,product_id) do update set quantity=10;
insert into public.inventory_valuation_balances(organization_id,location_id,product_id,quantity,carrying_value,average_unit_cost)
values ('88888888-0000-4888-8888-000000000000','88888888-0000-4888-8888-000000000001','88888888-0000-4888-8888-000000000002',10,500,50)
on conflict (location_id,product_id) do update set quantity=10,carrying_value=500,average_unit_cost=50;
insert into public.manufacturing_work_orders(id,organization_id,location_id,output_product_id,planned_quantity,status,created_by)
values ('88888888-0000-4888-8888-000000000004','88888888-0000-4888-8888-000000000000','88888888-0000-4888-8888-000000000001','88888888-0000-4888-8888-000000000003',2,'in_progress','88888888-8888-4888-8888-888888888888');
insert into public.manufacturing_work_order_components(organization_id,work_order_id,component_product_id,quantity_per_output)
values ('88888888-0000-4888-8888-000000000000','88888888-0000-4888-8888-000000000004','88888888-0000-4888-8888-000000000002',1.5);
update public.manufacturing_work_orders set status='completed',completed_quantity=2
where organization_id='88888888-0000-4888-8888-000000000000' and id='88888888-0000-4888-8888-000000000004';

select has_table('public','manufacturing_work_orders','manufacturing work orders schema exists');
select has_table('public','manufacturing_work_order_components','manufacturing BOM component schema exists');
select has_column('public','supplier_bills','exchange_rate_to_kes','AP transaction-to-functional FX rate exists');
select has_column('public','sales_documents','exchange_rate_to_kes','AR transaction-to-functional FX rate exists');
select has_column('public','document_payments','settlement_exchange_rate_to_kes','AR settlement FX rate exists');
select has_function('public','get_cash_flow_forecast',ARRAY['uuid','integer'],'cash flow forecast RPC exists');
select has_trigger('public','manufacturing_work_orders','manufacturing_work_order_completion_reflection','completion trigger is installed');
select is((select quantity from public.inventory_balances where organization_id='88888888-0000-4888-8888-000000000000' and location_id='88888888-0000-4888-8888-000000000001' and product_id='88888888-0000-4888-8888-000000000002'),7::numeric,'manufacturing consumes component quantity atomically');
select is((select quantity from public.inventory_balances where organization_id='88888888-0000-4888-8888-000000000000' and location_id='88888888-0000-4888-8888-000000000001' and product_id='88888888-0000-4888-8888-000000000003'),2::numeric,'manufacturing reflects finished quantity');
select is((select carrying_value from public.inventory_valuation_balances where organization_id='88888888-0000-4888-8888-000000000000' and location_id='88888888-0000-4888-8888-000000000001' and product_id='88888888-0000-4888-8888-000000000003'),150::numeric,'finished stock receives component carrying value');
select is((select average_unit_cost from public.inventory_valuation_balances where organization_id='88888888-0000-4888-8888-000000000000' and location_id='88888888-0000-4888-8888-000000000001' and product_id='88888888-0000-4888-8888-000000000003'),75::numeric,'finished stock moving weighted average is calculated');

insert into public.sales_documents(id,organization_id,document_number,document_type,status,currency_code,exchange_rate_to_kes,grand_total,issued_at)
values ('88888888-0000-4888-8888-000000000005','88888888-0000-4888-8888-000000000000','FX-AR-TEST','sale','issued','USD',150,100,now());
insert into public.document_payments(organization_id,document_id,tender_type,idempotency_key,amount,currency_code,status,received_amount,settlement_exchange_rate_to_kes,confirmed_at)
values ('88888888-0000-4888-8888-000000000000','88888888-0000-4888-8888-000000000005','cash','sprint2-ar-fx-test-key',100,'USD','succeeded',100,155,now());
select ok(exists(select 1 from public.journal_entries where organization_id='88888888-0000-4888-8888-000000000000' and source_type='document_payment' and source_id=(select id from public.document_payments where idempotency_key='sprint2-ar-fx-test-key') and posting_purpose='realized_fx'),'customer settlement creates an idempotent realized FX journal');

insert into public.suppliers(id,organization_id,name,supplier_code)
values ('88888888-0000-4888-8888-000000000006','88888888-0000-4888-8888-000000000000','FX Test Supplier','FX-TEST');
insert into public.supplier_bills(id,organization_id,supplier_id,supplier_invoice_number,bill_date,currency_code,exchange_rate_to_kes,subtotal,input_tax)
values ('88888888-0000-4888-8888-000000000007','88888888-0000-4888-8888-000000000000','88888888-0000-4888-8888-000000000006','FX-BILL-TEST',current_date,'USD',150,100,0);
insert into public.supplier_bill_payments(organization_id,bill_id,tender_type,idempotency_key,amount,settlement_exchange_rate_to_kes)
values ('88888888-0000-4888-8888-000000000000','88888888-0000-4888-8888-000000000007','bank_transfer','sprint2-ap-fx-test-key',100,155);
select ok(exists(select 1 from public.journal_entries where organization_id='88888888-0000-4888-8888-000000000000' and source_type='supplier_bill_payment' and source_id=(select id from public.supplier_bill_payments where idempotency_key='sprint2-ap-fx-test-key') and posting_purpose='realized_fx'),'supplier settlement creates an idempotent realized FX journal');

set local role authenticated;
select set_config('request.jwt.claim.sub','88888888-8888-4888-8888-888888888888',true);
select is((select count(*)::int from public.get_cash_flow_forecast('88888888-0000-4888-8888-000000000000',30)),61,'forecast returns 30 historical days, today, and 30 future days');
reset role;

select * from finish();
rollback;
