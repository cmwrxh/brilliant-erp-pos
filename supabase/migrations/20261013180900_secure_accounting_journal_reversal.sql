-- Require tenant membership and an accounting role before reading or reversing a journal.
-- This is an additive fix; do not rewrite migration 0014 after it has been applied.
create or replace function public.reverse_accounting_journal(
  p_organization_id uuid,
  p_original_journal_id uuid,
  p_reversal_date date,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  caller uuid := auth.uid();
  caller_role text;
  service_call boolean := coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role';
  original public.journal_entries%rowtype;
  reversal_id uuid;
  reverse_lines jsonb;
begin
  if not service_call then
    if caller is null then
      raise exception 'Authentication required.' using errcode='28000';
    end if;

    select role::text into caller_role
      from public.organization_members
      where organization_id=p_organization_id and user_id=caller;

    if caller_role is null or caller_role not in ('owner','admin','manager') then
      raise exception 'Not authorized to reverse accounting journals.' using errcode='42501';
    end if;
  end if;

  if length(trim(coalesce(p_reason,'')))<5 then
    raise exception 'A meaningful reversal reason is required.' using errcode='22023';
  end if;

  select * into original from public.journal_entries
    where organization_id=p_organization_id and id=p_original_journal_id and status='posted';

  if not found then
    raise exception 'Only an existing posted journal can be reversed.' using errcode='P0002';
  end if;

  if original.reversed_entry_id is not null or original.source_type='reversal' then
    raise exception 'A reversal journal cannot itself be reversed through this function.' using errcode='23514';
  end if;

  select jsonb_agg(jsonb_build_object(
    'account_id',l.account_id,
    'debit',l.credit,
    'credit',l.debit,
    'description',coalesce(l.description,'Reversal: ') || ' [reversal]',
    'source_reference',coalesce(l.source_reference,original.source_type||':'||original.source_id::text)
  ) order by l.line_number)
  into reverse_lines from public.journal_lines l
  where l.organization_id=p_organization_id and l.journal_entry_id=original.id;

  if reverse_lines is null then
    raise exception 'Original journal has no lines.' using errcode='23514';
  end if;

  reversal_id := public.post_accounting_journal(
    p_organization_id,
    p_reversal_date,
    'Reversal of journal '||original.journal_number||': '||left(trim(p_reason),400),
    'reversal',
    original.id,
    'reversal',
    reverse_lines,
    original.id
  );

  return reversal_id;
end;
$function$;

revoke all on function public.reverse_accounting_journal(uuid,uuid,date,text) from public, anon;
grant execute on function public.reverse_accounting_journal(uuid,uuid,date,text) to authenticated, service_role;
