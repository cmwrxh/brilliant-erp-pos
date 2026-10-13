-- Idempotent, tenant-scoped M-PESA settlement matching.
create unique index mpesa_settlement_payment_once_idx
  on public.mpesa_settlement_matches(organization_id,payment_id);

create or replace function public.match_mpesa_settlement_payments(
  p_organization_id uuid,
  p_settlement_id uuid,
  p_payment_ids uuid[]
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  settlement public.mpesa_settlements%rowtype;
  payment_total numeric(16,2);
  payment_count integer;
  matched_count integer;
begin
  if caller_id is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  select role::text into caller_role from public.organization_members
   where organization_id=p_organization_id and user_id=caller_id;
  if caller_role is null or caller_role not in ('owner','admin','manager') then
    raise exception 'Not authorized to reconcile M-PESA settlements.' using errcode='42501';
  end if;
  if p_payment_ids is null or cardinality(p_payment_ids)=0
     or cardinality(p_payment_ids)<>(select count(distinct x) from unnest(p_payment_ids) x) then
    raise exception 'Provide a non-empty list of distinct payment IDs.' using errcode='22023';
  end if;
  select * into settlement from public.mpesa_settlements
   where organization_id=p_organization_id and id=p_settlement_id for update;
  if not found then raise exception 'Settlement not found for this business.' using errcode='23503'; end if;
  if settlement.status in ('matched','posted') then
    select count(*) into matched_count from public.mpesa_settlement_matches
     where organization_id=p_organization_id and settlement_id=p_settlement_id;
    if matched_count=cardinality(p_payment_ids) and not exists(
      select 1 from unnest(p_payment_ids) x
      where not exists(select 1 from public.mpesa_settlement_matches m
       where m.organization_id=p_organization_id and m.settlement_id=p_settlement_id and m.payment_id=x)
    ) then
      return jsonb_build_object('status',settlement.status,'matched_payments',matched_count,'gross_amount',settlement.gross_amount,'payment_total',settlement.gross_amount,'variance',0);
    end if;
    raise exception 'This settlement is already matched; create a reviewed correction instead of replacing matches.' using errcode='23514';
  end if;
  select count(*),coalesce(sum(p.received_amount),0)
    into payment_count,payment_total
  from public.document_payments p
  where p.organization_id=p_organization_id and p.id=any(p_payment_ids)
    and p.tender_type='mpesa' and p.status='succeeded'
    and p.confirmed_at between settlement.period_start and settlement.period_end;
  if payment_count<>cardinality(p_payment_ids) then
    raise exception 'Every payment must be a confirmed M-PESA payment inside the settlement period.' using errcode='23514';
  end if;
  if exists(select 1 from public.mpesa_settlement_matches m
    where m.organization_id=p_organization_id and m.payment_id=any(p_payment_ids)) then
    raise exception 'One or more payments are already matched to another settlement.' using errcode='23505';
  end if;
  if round(payment_total,2)<>settlement.gross_amount then
    update public.mpesa_settlements set status='variance'
     where organization_id=p_organization_id and id=p_settlement_id;
    return jsonb_build_object('status','variance','matched_payments',0,'gross_amount',settlement.gross_amount,'payment_total',round(payment_total,2),'variance',round(settlement.gross_amount-payment_total,2));
  end if;
  insert into public.mpesa_settlement_matches(organization_id,settlement_id,payment_id,matched_amount,matched_by)
  select p_organization_id,p_settlement_id,p.id,p.received_amount,caller_id
  from public.document_payments p where p.organization_id=p_organization_id and p.id=any(p_payment_ids);
  update public.mpesa_settlements set status='matched'
   where organization_id=p_organization_id and id=p_settlement_id;
  return jsonb_build_object('status','matched','matched_payments',payment_count,'gross_amount',settlement.gross_amount,'payment_total',round(payment_total,2),'variance',0);
end;
$$;
revoke all on function public.match_mpesa_settlement_payments(uuid,uuid,uuid[]) from public,anon;
grant execute on function public.match_mpesa_settlement_payments(uuid,uuid,uuid[]) to authenticated;
