-- Remove inherited/default anonymous table grants on the SafariPOS accounting schema.
-- Authenticated users retain read access governed by RLS; posting remains RPC-only.
revoke all on public.accounting_settings,
  public.chart_of_accounts,
  public.accounting_periods,
  public.journal_entries,
  public.journal_lines,
  public.accounting_audit_log
from anon;

revoke insert, update, delete on public.accounting_settings,
  public.chart_of_accounts,
  public.accounting_periods,
  public.journal_entries,
  public.journal_lines,
  public.accounting_audit_log
from authenticated;

grant select on public.accounting_settings,
  public.chart_of_accounts,
  public.accounting_periods,
  public.journal_entries,
  public.journal_lines
to authenticated;

grant select on public.accounting_audit_log to authenticated;
