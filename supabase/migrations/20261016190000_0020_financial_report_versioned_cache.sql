-- Durable, tenant-isolated versioned cache for reports whose requested dates are in a closed period.
-- Version timestamps are bumped transactionally with every report-affecting ledger/account mutation.
create table public.financial_report_cache_versions (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  latest_transaction_at timestamptz not null default clock_timestamp()
);

create table public.financial_report_cache (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  latest_transaction_at timestamptz not null,
  report_data jsonb not null,
  created_at timestamptz not null default now(),
  primary key (organization_id, period_start, period_end, latest_transaction_at),
  check (period_end >= period_start)
);

create index financial_report_cache_org_period_idx
  on public.financial_report_cache (organization_id, period_end desc);

create or replace function public.bump_financial_report_cache_version()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare target_org uuid;
begin
  if TG_OP = 'DELETE' then
    target_org := OLD.organization_id;
  else
    target_org := NEW.organization_id;
  end if;

  insert into public.financial_report_cache_versions (organization_id, latest_transaction_at)
  values (target_org, clock_timestamp())
  on conflict (organization_id) do update
    set latest_transaction_at = greatest(clock_timestamp(), public.financial_report_cache_versions.latest_transaction_at + interval '1 microsecond');

  if TG_OP = 'DELETE' then return OLD; end if;
  return NEW;
end;
$$;

create trigger financial_cache_version_journal_entries
after insert or update or delete on public.journal_entries
for each row execute function public.bump_financial_report_cache_version();

create trigger financial_cache_version_journal_lines
after insert or update or delete on public.journal_lines
for each row execute function public.bump_financial_report_cache_version();

create trigger financial_cache_version_chart_accounts
after insert or update or delete on public.chart_of_accounts
for each row execute function public.bump_financial_report_cache_version();

alter table public.financial_report_cache_versions enable row level security;
alter table public.financial_report_cache enable row level security;

create policy "Members read financial cache version"
on public.financial_report_cache_versions for select to authenticated
using (public.is_organization_member(organization_id));

create policy "Members read financial report cache"
on public.financial_report_cache for select to authenticated
using (public.is_organization_member(organization_id));

create policy "Members insert financial report cache"
on public.financial_report_cache for insert to authenticated
with check (public.is_organization_member(organization_id));

create policy "Members update financial report cache"
on public.financial_report_cache for update to authenticated
using (public.is_organization_member(organization_id))
with check (public.is_organization_member(organization_id));

revoke all on function public.bump_financial_report_cache_version() from public, anon, authenticated;
