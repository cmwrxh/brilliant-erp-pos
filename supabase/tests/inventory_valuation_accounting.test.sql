create extension if not exists pgtap with schema extensions;
begin;
select plan(12);
select has_table('public','inventory_valuation_balances','moving-average valuation balance table exists');
select has_table('public','inventory_valuation_movements','valuation movement ledger exists');
select ok(
  (select relrowsecurity from pg_class where oid='public.inventory_valuation_balances'::regclass)
  and (select relrowsecurity from pg_class where oid='public.inventory_valuation_movements'::regclass),
  'RLS protects inventory valuation tables'
);
select ok(
  has_function_privilege('authenticated','public.record_inventory_receipt_valued(uuid,uuid,uuid,numeric,numeric,text)','execute')
  and not has_function_privilege('authenticated','public.record_inventory_movement(uuid,uuid,uuid,text,numeric,text)','execute'),
  'stock receipt uses the valued RPC, not the legacy unvalued movement RPC'
);
select ok(
  not has_function_privilege('authenticated','public.post_accounting_journal_internal(uuid,date,text,text,uuid,text,jsonb,uuid)','execute'),
  'private posting function is not executable by API roles'
);
select ok(
  exists(select 1 from pg_trigger where tgname='apply_sale_inventory_valuation_after_movement' and not tgisinternal)
  and exists(select 1 from pg_trigger where tgname='post_completed_sale_to_ledger_after_completion' and not tgisinternal),
  'sale movements update valuation and completed sales post journals'
);
select ok(
  exists(select 1 from public.organizations o join public.accounting_settings s on s.organization_id=o.id)
  and exists(select 1 from public.organizations o join public.chart_of_accounts a on a.organization_id=o.id and a.system_key='goods_received_not_invoiced'),
  'existing businesses have accounting settings and the inventory receipt clearing account'
);

create temporary table _safaripos_accounting_test_context(organization_id uuid, sale_id uuid) on commit drop;
do $$
declare
  org_id uuid := gen_random_uuid();
  loc_id uuid := gen_random_uuid();
  product_id uuid := gen_random_uuid();
  sale_id uuid := gen_random_uuid();
  inventory_account uuid;
  capital_account uuid;
begin
  insert into public.organizations(id,name,slug) values(org_id,'Accounting Sale Test','acct-sale-'||substr(replace(org_id::text,'-',''),1,12));
  insert into public.locations(id,organization_id,name,code) values(loc_id,org_id,'Test branch','MAIN');
  insert into public.products(id,organization_id,sku,name,unit,cost_price,selling_price,tax_rate)
    values(product_id,org_id,'TESTSKU','Test item','each',100,500,16);
  insert into public.inventory_balances(organization_id,location_id,product_id,quantity,reorder_level)
    values(org_id,loc_id,product_id,5,0);
  insert into public.inventory_valuation_balances(organization_id,location_id,product_id,quantity,carrying_value,average_unit_cost)
    values(org_id,loc_id,product_id,5,500,100);
  select id into inventory_account from public.chart_of_accounts where organization_id=org_id and system_key='inventory';
  select id into capital_account from public.chart_of_accounts where organization_id=org_id and system_key='owner_capital';
  perform public.post_accounting_journal_internal(org_id,current_date,'Opening inventory test','opening',gen_random_uuid(),'opening',
    jsonb_build_array(
      jsonb_build_object('account_id',inventory_account,'debit',500,'credit',0,'description','Opening inventory'),
      jsonb_build_object('account_id',capital_account,'debit',0,'credit',500,'description','Opening capital')
    ),null);
  insert into public.sales(id,organization_id,location_id,receipt_number,currency_code,subtotal,discount_total,tax_total,grand_total,status)
    values(sale_id,org_id,loc_id,'TEST-RECEIPT','KES',1000,0,160,1160,'draft');
  insert into public.sale_items(organization_id,sale_id,product_id,product_name_snapshot,sku_snapshot,quantity,unit_price,discount_amount,tax_amount,line_total)
    values(org_id,sale_id,product_id,'Test item','TESTSKU',2,500,0,160,1160);
  insert into public.sale_payments(organization_id,sale_id,method,amount,status)
    values(org_id,sale_id,'cash',1160,'recorded');
  update public.inventory_balances set quantity=3,updated_at=now()
    where organization_id=org_id and location_id=loc_id and product_id=product_id;
  insert into public.inventory_movements(organization_id,location_id,product_id,movement_type,quantity_delta,quantity_before,quantity_after,reference_type,reference_id)
    values(org_id,loc_id,product_id,'sale',-2,5,3,'sale',sale_id);
  update public.sales set status='completed' where id=sale_id and organization_id=org_id;
  insert into _safaripos_accounting_test_context values(org_id,sale_id);
end $$;

select is(
  (select quantity from public.inventory_valuation_balances v join _safaripos_accounting_test_context c using(organization_id) where v.location_id=(select location_id from public.sales where id=c.sale_id) limit 1),
  3::numeric,
  'sale reduces valued inventory quantity'
);
select is(
  (select v.carrying_value from public.inventory_valuation_balances v join _safaripos_accounting_test_context c using(organization_id) join public.sales s on s.id=c.sale_id and s.organization_id=v.organization_id where v.location_id=s.location_id limit 1),
  300::numeric,
  'sale reduces moving-average inventory value to 300'
);
select ok(
  (select coalesce(sum(case when l.account_id=a.id then l.debit-l.credit else 0 end),0)
   from _safaripos_accounting_test_context c
   join public.chart_of_accounts a on a.organization_id=c.organization_id and a.system_key='inventory'
   join public.journal_entries j on j.organization_id=c.organization_id and j.status='posted'
   join public.journal_lines l on l.organization_id=j.organization_id and l.journal_entry_id=j.id
   where c.organization_id=a.organization_id) = 300,
  'inventory GL control account reconciles to valuation after the sale'
);
select ok(
  (select (select count(*)=3 from _safaripos_accounting_test_context c join public.journal_entries j on j.organization_id=c.organization_id and j.status='posted') and sum_debit=sum_credit from (
    select coalesce(sum(l.debit),0) as sum_debit,coalesce(sum(l.credit),0) as sum_credit
    from _safaripos_accounting_test_context c join public.journal_entries j on j.organization_id=c.organization_id and j.status='posted'
    join public.journal_lines l on l.organization_id=j.organization_id and l.journal_entry_id=j.id
    group by c.organization_id
  ) q),
  'opening, revenue and COGS journals all balance'
);
select is(
  (select coalesce(sum(l.debit-l.credit),0) from _safaripos_accounting_test_context c
   join public.chart_of_accounts a on a.organization_id=c.organization_id and a.system_key='cogs'
   join public.journal_entries j on j.organization_id=c.organization_id and j.source_type='sale' and j.posting_purpose='cogs'
   join public.journal_lines l on l.organization_id=j.organization_id and l.journal_entry_id=j.id and l.account_id=a.id),
  200::numeric,
  'sale posts weighted-average cost of goods sold'
);
select * from finish();
rollback;
