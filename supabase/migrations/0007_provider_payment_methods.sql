-- Preserve the actual payment provider on each recorded sale payment.
alter table public.sale_payments drop constraint if exists sale_payments_method_check;
alter table public.sale_payments add constraint sale_payments_method_check
  check (method in ('cash','mpesa','airtel_money','flutterwave','paystack','card','bank_transfer','credit','other'));

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
  if p_method not in ('cash','mpesa','airtel_money','flutterwave','paystack','card','bank_transfer','credit','other') then raise exception 'Invalid payment method' using errcode = '22023'; end if;
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
