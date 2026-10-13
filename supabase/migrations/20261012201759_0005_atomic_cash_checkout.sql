-- Atomic cash checkout: draft creation, stock decrement, movement ledger and payment all commit or roll back together.
create or replace function public.checkout_sale(
  p_organization_id uuid,
  p_location_id uuid,
  p_items jsonb,
  p_customer_id uuid default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  created_sale_id uuid;
  total_due numeric(14,2);
begin
  created_sale_id := public.create_sale_draft(p_organization_id,p_location_id,p_items,p_customer_id);
  select grand_total into total_due from public.sales where id=created_sale_id and organization_id=p_organization_id;
  if total_due <= 0 then raise exception 'Sale total must be greater than zero' using errcode = '23514'; end if;
  perform public.complete_sale(p_organization_id,created_sale_id,'cash',total_due,null);
  return created_sale_id;
end;
$$;
revoke all on function public.checkout_sale(uuid,uuid,jsonb,uuid) from public, anon;
grant execute on function public.checkout_sale(uuid,uuid,jsonb,uuid) to authenticated;
