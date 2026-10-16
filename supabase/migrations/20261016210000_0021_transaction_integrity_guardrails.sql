-- Transaction-integrity guardrails: serialize posting with period close and reject all writes into locked periods.
-- Checkout, stock deductions, sale-ledger posting and eTIMS snapshot enqueue already execute
-- as database triggers/RPCs in the same PostgreSQL transaction. Do not move these side effects
-- into independent API requests.

create or replace function public.guard_accounting_period_journal_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  has_periods boolean;
begin
  -- Use the same per-organization lock as both posting functions and period close,
  -- preventing a period from closing between the date check and journal commit.
  perform 1
    from public.accounting_settings
    where organization_id = NEW.organization_id
    for update;

  if not found then
    raise exception 'Accounting settings are not initialized for this organization.'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.accounting_periods p
    where p.organization_id = NEW.organization_id
      and p.status = 'closed'
      and NEW.accounting_date between p.starts_on and p.ends_on
  ) then
    raise exception 'Accounting period is closed; posted transactions cannot be written into it.'
      using errcode = '23514';
  end if;

  select exists (
    select 1 from public.accounting_periods p
    where p.organization_id = NEW.organization_id
  ) into has_periods;

  if has_periods and not exists (
    select 1
    from public.accounting_periods p
    where p.organization_id = NEW.organization_id
      and p.status = 'open'
      and NEW.accounting_date between p.starts_on and p.ends_on
  ) then
    raise exception 'Accounting date is outside an open accounting period.'
      using errcode = '23514';
  end if;

  return NEW;
end;
$$;

drop trigger if exists journal_entries_period_write_guard on public.journal_entries;
create trigger journal_entries_period_write_guard
before insert or update of accounting_date, status on public.journal_entries
for each row execute function public.guard_accounting_period_journal_write();

revoke all on function public.guard_accounting_period_journal_write() from public, anon, authenticated;

-- Period close takes the same organization lock as posting, then locks the period row.
-- This makes close/post mutually exclusive rather than dependent on timing.
create or replace function public.close_accounting_period(
  p_organization_id uuid,
  p_period_id uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null or not exists (
    select 1 from public.organization_members m
    where m.organization_id = p_organization_id
      and m.user_id = caller
      and m.role in ('owner','admin')
  ) then
    raise exception 'Only a workspace owner/admin can close a period.'
      using errcode = '42501';
  end if;

  perform 1
  from public.accounting_settings s
  where s.organization_id = p_organization_id
  for update;

  if not found then
    raise exception 'Accounting settings are not initialized for this organization.'
      using errcode = '23514';
  end if;

  perform 1
  from public.accounting_periods p
  where p.id = p_period_id
    and p.organization_id = p_organization_id
    and p.status = 'open'
  for update;

  if not found then
    raise exception 'Open accounting period not found.'
      using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.journal_entries j
    where j.organization_id = p_organization_id
      and j.status = 'draft'
  ) then
    raise exception 'Draft journals must be resolved before close.'
      using errcode = '23514';
  end if;

  update public.accounting_periods
  set status = 'closed',
      closed_at = now(),
      closed_by = caller,
      close_note = left(p_note, 500)
  where id = p_period_id
    and organization_id = p_organization_id
    and status = 'open';

  if not found then
    raise exception 'Accounting period was closed concurrently; retry.'
      using errcode = '40001';
  end if;
end;
$$;

revoke all on function public.close_accounting_period(uuid,uuid,text) from public, anon;
grant execute on function public.close_accounting_period(uuid,uuid,text) to authenticated;

comment on function public.guard_accounting_period_journal_write() is
  'Rejects journal writes dated in closed periods and serializes journal writes against period close.';
