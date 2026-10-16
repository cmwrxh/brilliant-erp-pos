-- Durable, tenant-scoped eTIMS queue and audit trail.
-- This migration does not enable live KRA submissions or certify a KRA protocol.
create table if not exists public.kra_etims_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  source_sale_id uuid not null,
  receipt_number text not null,
  payload_snapshot jsonb not null,
  status text not null default 'queued'
    check (status in ('queued','retry','accepted','rejected','requires_review','blocked')),
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  last_error text,
  fiscal_receipt_number text,
  fiscal_signature text,
  submitted_at timestamptz,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, source_sale_id),
  foreign key (organization_id, source_sale_id)
    references public.sales(organization_id, id) on delete restrict
);
create index if not exists kra_etims_outbox_retry_idx
  on public.kra_etims_outbox(status, next_attempt_at)
  where status in ('queued','retry','blocked');

create table if not exists public.kra_etims_audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  outbox_id uuid references public.kra_etims_outbox(id) on delete restrict,
  source_sale_id uuid,
  event_type text not null check (char_length(trim(event_type)) between 2 and 80),
  outcome text not null check (outcome in ('queued','accepted','rejected','retry','blocked','error')),
  message text,
  response_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (organization_id, source_sale_id)
    references public.sales(organization_id, id) on delete restrict
);
create index if not exists kra_etims_audit_org_created_idx
  on public.kra_etims_audit_logs(organization_id, created_at desc);

alter table public.kra_etims_outbox enable row level security;
alter table public.kra_etims_audit_logs enable row level security;

drop policy if exists "Members read eTIMS outbox" on public.kra_etims_outbox;
create policy "Members read eTIMS outbox" on public.kra_etims_outbox
  for select to authenticated using (public.is_organization_member(organization_id));
drop policy if exists "Members enqueue eTIMS outbox" on public.kra_etims_outbox;
create policy "Members enqueue eTIMS outbox" on public.kra_etims_outbox
  for insert to authenticated with check (public.is_organization_member(organization_id));
drop policy if exists "Members read eTIMS audit logs" on public.kra_etims_audit_logs;
create policy "Members read eTIMS audit logs" on public.kra_etims_audit_logs
  for select to authenticated using (public.is_organization_member(organization_id));
drop policy if exists "Members append eTIMS audit logs" on public.kra_etims_audit_logs;
create policy "Members append eTIMS audit logs" on public.kra_etims_audit_logs
  for insert to authenticated with check (public.is_organization_member(organization_id));

revoke update, delete on public.kra_etims_outbox from anon, authenticated;
revoke update, delete on public.kra_etims_audit_logs from anon, authenticated;
grant select, insert on public.kra_etims_outbox to authenticated;
grant select, insert on public.kra_etims_audit_logs to authenticated;

comment on table public.kra_etims_outbox is
  'Durable retry queue. Live submission remains blocked until the applicable KRA OSCU/VSCU adapter is reviewed and certified.';
