-- Harden stock writes and make sale creation/completion transactional.
alter table public.sales alter column status set default 'draft';

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  product_id uuid not null,
  movement_type text not null check (movement_type in ('opening','receiving','adjustment','sale','return','reversal')),
  quantity_delta numeric(14,3) not null check (quantity_delta <> 0),
  quantity_before numeric(14,3) not null,
  quantity_after numeric(14,3) not null check (quantity_after >= 0),
  reference_type text,
  reference_id uuid,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (organization_id,location_id) references public.locations(organization_id,id),
  foreign key (organization_id,product_id) references public.products(organization_id,id),
  check (quantity_after = quantity_before + quantity_delta)
);
create index inventory_movements_org_created_idx on public.inventory_movements(organization_id,created_at desc);
create index inventory_movements_product_idx on public.inventory_movements(organization_id,location_id,product_id,created_at desc);
alter table public.inventory_movements enable row level security;
create policy "Members read inventory movements" on public.inventory_movements for select to authenticated using (public.is_organization_member(organization_id));
revoke insert, update, delete on public.inventory_movements from anon, authenticated;
revoke insert, update, delete on public.inventory_balances from anon, authenticated;
drop policy if exists "Inventory staff manage balances" on public.inventory_balances;
revoke insert, update, delete on public.sales from anon, authenticated;
revoke insert, update, delete on public.sale_items from anon, authenticated;
revoke insert, update, delete on public.sale_payments from anon, authenticated;

create or replace function public.record_inventory_movement(
  p_organization_id uuid,
  p_location_id uuid,
  p_product_id uuid,
  p_movement_type text,
  p_quantity_delta numeric,
  p_note text default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role public.business_role;
  before_qty numeric(14,3);
  after_qty numeric(14,3);
  movement_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_movement_type not in ('opening','receiving','adjustment','return','reversal') then raise exception 'Invalid stock movement type' using errcode = '22023'; end if;
  if p_quantity_delta is null or p_quantity_delta = 0 then raise exception 'Quantity change must be non-zero' using errcode = '22023'; end if;
  select role into caller_role from public.organization_members where organization_id=p_organization_id and user_id=caller_id;
  if caller_role is null or caller_role not in ('owner','admin','manager','inventory') then raise exception 'Not authorized for stock movements' using errcode = '42501'; end if;
  if p_movement_type in ('adjustment','opening','reversal') and caller_role not in ('owner','admin','manager') then
    raise exception 'Only managers can make adjustments, opening entries or reversals' using errcode = '42501';
  end if;
  if not exists (select 1 from public.locations where id=p_location_id and organization_id=p_organization_id and is_active)
     or not exists (select 1 from public.products where id=p_product_id and organization_id=p_organization_id and is_active) then
    raise exception 'Invalid or inactive location/product for this workspace' using errcode = '23503';
  end if;
  insert into public.inventory_balances(organization_id,location_id,product_id,quantity,reorder_level)
  values (p_organization_id,p_location_id,p_product_id,0,0)
  on conflict (location_id,product_id) do nothing;
  select quantity into before_qty from public.inventory_balances
    where organization_id=p_organization_id and location_id=p_location_id and product_id=p_product_id for update;
  after_qty := before_qty + p_quantity_delta;
  if after_qty < 0 then raise exception 'Stock cannot become negative' using errcode = '23514'; end if;
  update public.inventory_balances set quantity=after_qty,updated_at=now()
    where organization_id=p_organization_id and location_id=p_location_id and product_id=p_product_id;
  insert into public.inventory_movements(organization_id,location_id,product_id,movement_type,quantity_delta,quantity_before,quantity_after,note,created_by)
  values (p_organization_id,p_location_id,p_product_id,p_movement_type,p_quantity_delta,before_qty,after_qty,left(p_note,500),caller_id)
  returning id into movement_id;
  return movement_id;
end;
$$;
revoke all on function public.record_inventory_movement(uuid,uuid,uuid,text,numeric,text) from public, anon;
grant execute on function public.record_inventory_movement(uuid,uuid,uuid,text,numeric,text) to authenticated;

create or replace function public.create_sale_draft(
  p_organization_id uuid,
  p_location_id uuid,
  p_items jsonb,
  p_customer_id uuid default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role public.business_role;
  item jsonb;
  product_row record;
  qty numeric(14,3);
  discount numeric(14,2);
  gross numeric(14,2);
  tax numeric(14,2);
  line_total numeric(14,2);
  subtotal_sum numeric(14,2) := 0;
  discount_sum numeric(14,2) := 0;
  tax_sum numeric(14,2) := 0;
  total_sum numeric(14,2) := 0;
  new_sale_id uuid := gen_random_uuid();
  receipt text := 'POS-' || to_char(now() at time zone 'Africa/Nairobi','YYYYMMDD') || '-' || upper(substr(replace(new_sale_id::text,'-',''),1,8));
begin
  if caller_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  select role into caller_role from public.organization_members where organization_id=p_organization_id and user_id=caller_id;
  if caller_role is null or caller_role not in ('owner','admin','manager','cashier') then raise exception 'Not authorized to create sales' using errcode = '42501'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 100 then
    raise exception 'A sale must contain between 1 and 100 line items' using errcode = '22023';
  end if;
  if not exists(select 1 from public.locations where id=p_location_id and organization_id=p_organization_id and is_active) then
    raise exception 'Invalid or inactive sale location' using errcode = '23503';
  end if;
  if p_customer_id is not null and not exists(select 1 from public.customers where id=p_customer_id and organization_id=p_organization_id) then
    raise exception 'Customer does not belong to this workspace' using errcode = '23503';
  end if;
  for item in select value from jsonb_array_elements(p_items) loop
    if not (item ? 'product_id') then raise exception 'Product ID is required for every line' using errcode = '22023'; end if;
    qty := (item->>'quantity')::numeric;
    discount := coalesce((item->>'discount_amount')::numeric,0);
    if qty <= 0 or qty > 100000 or discount < 0 then raise exception 'Invalid quantity or discount' using errcode = '22023'; end if;
    select id,sku,name,selling_price,tax_rate,is_active into product_row from public.products
      where id=(item->>'product_id')::uuid and organization_id=p_organization_id for share;
    if not found or not product_row.is_active then raise exception 'Product not found or inactive' using errcode = '23503'; end if;
    gross := round(product_row.selling_price * qty,2);
    if discount > gross then raise exception 'Discount cannot exceed line value' using errcode = '22023'; end if;
    tax := round((gross-discount)*product_row.tax_rate/100,2);
    line_total := gross-discount+tax;
    subtotal_sum := subtotal_sum+gross;
    discount_sum := discount_sum+discount;
    tax_sum := tax_sum+tax;
    total_sum := total_sum+line_total;
  end loop;
  insert into public.sales(id,organization_id,location_id,receipt_number,customer_id,cashier_user_id,currency_code,subtotal,discount_total,tax_total,grand_total,status)
  values(new_sale_id,p_organization_id,p_location_id,receipt,p_customer_id,caller_id,'KES',subtotal_sum,discount_sum,tax_sum,total_sum,'draft');
  for item in select value from jsonb_array_elements(p_items) loop
    qty := (item->>'quantity')::numeric;
    discount := coalesce((item->>'discount_amount')::numeric,0);
    select id,sku,name,selling_price,tax_rate into product_row from public.products
      where id=(item->>'product_id')::uuid and organization_id=p_organization_id;
    gross := round(product_row.selling_price*qty,2);
    tax := round((gross-discount)*product_row.tax_rate/100,2);
    line_total := gross-discount+tax;
    insert into public.sale_items(organization_id,sale_id,product_id,product_name_snapshot,sku_snapshot,quantity,unit_price,discount_amount,tax_amount,line_total)
    values(p_organization_id,new_sale_id,product_row.id,product_row.name,product_row.sku,qty,product_row.selling_price,discount,tax,line_total);
  end loop;
  return new_sale_id;
end;
$$;
revoke all on function public.create_sale_draft(uuid,uuid,jsonb,uuid) from public, anon;
grant execute on function public.create_sale_draft(uuid,uuid,jsonb,uuid) to authenticated;

create or replace function public.complete_sale(
  p_organization_id uuid,
  p_sale_id uuid,
  p_method text,
  p_amount numeric,
  p_provider_reference text default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role public.business_role;
  service_call boolean := coalesce(current_setting('request.jwt.claim.role',true),'') = 'service_role';
  sale_row public.sales%rowtype;
  item_row record;
  before_qty numeric(14,3);
  after_qty numeric(14,3);
  movement_id uuid;
begin
  if not service_call then
    if caller_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
    select role into caller_role from public.organization_members where organization_id=p_organization_id and user_id=caller_id;
    if caller_role is null or caller_role not in ('owner','admin','manager','cashier') then raise exception 'Not authorized to complete sales' using errcode = '42501'; end if;
  end if;
  if p_method not in ('cash','mpesa','card','bank_transfer','credit','other') then raise exception 'Invalid payment method' using errcode = '22023'; end if;
  select * into sale_row from public.sales where id=p_sale_id and organization_id=p_organization_id for update;
  if not found then raise exception 'Sale not found' using errcode = 'P0002'; end if;
  if sale_row.status='completed' then return sale_row.id; end if;
  if sale_row.status <> 'draft' then raise exception 'Only draft sales can be completed' using errcode = '23514'; end if;
  if p_amount is null or round(p_amount,2) <> sale_row.grand_total then raise exception 'Payment amount must match the sale total' using errcode = '23514'; end if;
  for item_row in select product_id,quantity from public.sale_items where organization_id=p_organization_id and sale_id=p_sale_id order by product_id loop
    select quantity into before_qty from public.inventory_balances
      where organization_id=p_organization_id and location_id=sale_row.location_id and product_id=item_row.product_id for update;
    if not found or before_qty < item_row.quantity then raise exception 'Insufficient stock to complete sale' using errcode = '23514'; end if;
    after_qty := before_qty-item_row.quantity;
    update public.inventory_balances set quantity=after_qty,updated_at=now()
      where organization_id=p_organization_id and location_id=sale_row.location_id and product_id=item_row.product_id;
    insert into public.inventory_movements(organization_id,location_id,product_id,movement_type,quantity_delta,quantity_before,quantity_after,reference_type,reference_id,created_by)
    values(p_organization_id,sale_row.location_id,item_row.product_id,'sale',-item_row.quantity,before_qty,after_qty,'sale',p_sale_id,case when service_call then null else caller_id end)
    returning id into movement_id;
  end loop;
  insert into public.sale_payments(organization_id,sale_id,method,amount,provider_reference,status)
  values(p_organization_id,p_sale_id,p_method,p_amount,p_provider_reference,'recorded');
  update public.sales set status='completed' where id=p_sale_id and organization_id=p_organization_id;
  return p_sale_id;
end;
$$;
revoke all on function public.complete_sale(uuid,uuid,text,numeric,text) from public, anon;
grant execute on function public.complete_sale(uuid,uuid,text,numeric,text) to authenticated, service_role;

-- Authenticated clients may read balances, but only trusted RPCs can mutate stock.
