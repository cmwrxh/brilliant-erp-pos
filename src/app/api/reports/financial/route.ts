import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import type { BalanceSheetLine, DashboardPeriod, FinancialDashboardData, ProfitLossPoint } from "@/components/dashboard/financial-types";

type AccountType = "asset" | "liability" | "equity" | "revenue" | "expense";
type LedgerLine = {
  debit: number | string;
  credit: number | string;
  chart_of_accounts: { name: string; code: string; account_type: AccountType; system_key: string | null } | { name: string; code: string; account_type: AccountType; system_key: string | null }[] | null;
  journal_entries: { accounting_date: string; status: string } | { accounting_date: string; status: string }[] | null;
};

const relation = <T,>(value: T | T[] | null): T | null => Array.isArray(value) ? value[0] ?? null : value as T | null;
const isoDate = (date: Date) => date.toISOString().slice(0, 10);
const addDays = (date: Date, days: number) => new Date(date.getTime() + days * 86400000);

function dateRange(period: DashboardPeriod, today: Date, customStart?: string | null, customEnd?: string | null) {
  const end = customEnd && /^\d{4}-\d{2}-\d{2}$/.test(customEnd) ? customEnd : isoDate(today);
  if (customStart && /^\d{4}-\d{2}-\d{2}$/.test(customStart)) return { start: customStart, end };
  if (period === "ytd") return { start: `${today.getUTCFullYear()}-01-01`, end };
  const days = period === "7d" ? 7 : period === "90d" ? 90 : 30;
  return { start: isoDate(addDays(new Date(`${end}T00:00:00.000Z`), -(days - 1))), end };
}

export async function GET(request: Request) {
  try {
    const supabase = await createSupabaseServerClient();
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });

    const { data: memberships, error: membershipError } = await supabase
      .from("organization_members").select("organization_id").eq("user_id", auth.user.id)
      .order("organization_id").limit(1);
    if (membershipError) throw membershipError;
    const organizationId = memberships?.[0]?.organization_id;
    if (!organizationId) return NextResponse.json({ error: "No organization membership found." }, { status: 403 });

    const url = new URL(request.url);
    const requestedPeriod = url.searchParams.get("period");
    const period: DashboardPeriod = requestedPeriod === "7d" || requestedPeriod === "90d" || requestedPeriod === "ytd" ? requestedPeriod : "30d";
    const today = new Date();
    const { start, end } = dateRange(period, today, url.searchParams.get("start"), url.searchParams.get("end"));
    if (start > end || end > isoDate(today)) return NextResponse.json({ error: "Invalid reporting date range." }, { status: 400 });
    const requestedDays = Math.floor((new Date(`${end}T00:00:00.000Z`).getTime() - new Date(`${start}T00:00:00.000Z`).getTime()) / 86400000) + 1;
    const MAX_REPORT_DAYS = 366;
    if (!Number.isFinite(requestedDays) || requestedDays < 1 || requestedDays > MAX_REPORT_DAYS) {
      return NextResponse.json({ error: "Reporting ranges are limited to 366 days. Choose a shorter interval." }, { status: 400 });
    }

    // Cache only ranges fully contained in a closed period. The tenant-specific
    // version is updated transactionally by database triggers on journal and account changes.
    let cacheVersion: string | null = null;
    const { data: closedPeriod, error: closedPeriodError } = await supabase
      .from("accounting_periods").select("id")
      .eq("organization_id", organizationId).eq("status", "closed")
      .lte("starts_on", start).gte("ends_on", end).limit(1).maybeSingle();
    if (closedPeriodError) throw closedPeriodError;
    if (closedPeriod) {
      const { data: versionRow, error: versionError } = await supabase
        .from("financial_report_cache_versions").select("latest_transaction_at")
        .eq("organization_id", organizationId).maybeSingle();
      if (versionError) throw versionError;
      cacheVersion = versionRow?.latest_transaction_at ?? null;
      if (cacheVersion) {
        const { data: cached, error: cacheReadError } = await supabase
          .from("financial_report_cache").select("report_data")
          .eq("organization_id", organizationId).eq("period_start", start).eq("period_end", end)
          .eq("latest_transaction_at", cacheVersion).maybeSingle();
        if (cacheReadError) throw cacheReadError;
        if (cached?.report_data) {
          return NextResponse.json({ data: cached.report_data as FinancialDashboardData, period, start, end });
        }
      }
    }

    // One joined ledger read path avoids separate account and journal lookups.
    // The balance sheet requires lifetime balances through `end`, so fail closed
    // rather than silently returning a partial statement when history is too large.
    const lines: LedgerLine[] = [];
    const pageSize = 1000;
    const maxLedgerLines = 20000;
    for (let offset = 0; offset < maxLedgerLines; offset += pageSize) {
      const { data, error } = await supabase.from("journal_lines")
        .select("debit,credit,chart_of_accounts!inner(name,code,account_type,system_key),journal_entries!inner(accounting_date,status)")
        .eq("organization_id", organizationId).eq("journal_entries.status", "posted")
        .lte("journal_entries.accounting_date", end).order("id", { ascending: true })
        .range(offset, offset + pageSize - 1);
      if (error) throw error;
      const batch = (data ?? []) as unknown as LedgerLine[];
      lines.push(...batch);
      if (batch.length < pageSize) break;
      if (offset + pageSize >= maxLedgerLines) {
        return NextResponse.json({ error: "This ledger is too large for synchronous reporting. Use a pre-aggregated accounting report." }, { status: 413 });
      }
    }

    const accountBalances = new Map<string, { name: string; type: AccountType; amount: number }>();
    const buckets = new Map<string, ProfitLossPoint>();
    const startMs = new Date(`${start}T00:00:00.000Z`).getTime();
    const endMs = new Date(`${end}T00:00:00.000Z`).getTime();
    const spanDays = Math.max(1, Math.floor((endMs - startMs) / 86400000) + 1);
    const bucketCount = spanDays <= 14 ? Math.min(7, spanDays) : spanDays <= 45 ? 4 : 6;
    for (let i = 0; i < bucketCount; i++) {
      const from = new Date(startMs + Math.floor(i * spanDays / bucketCount) * 86400000);
      const to = new Date(startMs + Math.floor((i + 1) * spanDays / bucketCount - 1) * 86400000);
      const label = spanDays <= 14
        ? new Intl.DateTimeFormat("en-KE", { day: "2-digit", month: "short", timeZone: "UTC" }).format(from)
        : `${new Intl.DateTimeFormat("en-KE", { day: "2-digit", month: "short", timeZone: "UTC" }).format(from)}–${new Intl.DateTimeFormat("en-KE", { day: "2-digit", month: "short", timeZone: "UTC" }).format(to)}`;
      buckets.set(isoDate(from), { label, revenue: 0, expenses: 0, netProfit: 0 });
    }

    let revenue = 0, expenses = 0, lifetimeRevenue = 0, lifetimeExpenses = 0;
    for (const line of lines) {
      const account = relation(line.chart_of_accounts);
      const entry = relation(line.journal_entries);
      if (!account || !entry || entry.status !== "posted") continue;
      const debit = Number(line.debit) || 0, credit = Number(line.credit) || 0;
      const signed = account.account_type === "asset" || account.account_type === "expense" ? debit - credit : credit - debit;
      const prior = accountBalances.get(account.code) ?? { name: account.name, type: account.account_type, amount: 0 };
      prior.amount += signed;
      accountBalances.set(account.code, prior);
      if (entry.accounting_date <= end) {
        if (account.account_type === "revenue") lifetimeRevenue += signed;
        if (account.account_type === "expense") lifetimeExpenses += signed;
      }
      if (entry.accounting_date < start || entry.accounting_date > end) continue;
      if (account.account_type === "revenue") revenue += signed;
      if (account.account_type === "expense") expenses += signed;
      if (account.account_type === "revenue" || account.account_type === "expense") {
        const elapsed = Math.max(0, Math.floor((new Date(`${entry.accounting_date}T00:00:00.000Z`).getTime() - startMs) / 86400000));
        const bucketIndex = Math.min(bucketCount - 1, Math.floor(elapsed / spanDays * bucketCount));
        const bucketKey = Array.from(buckets.keys())[bucketIndex];
        const bucket = buckets.get(bucketKey);
        if (bucket) {
          if (account.account_type === "revenue") bucket.revenue += signed;
          else bucket.expenses += signed;
        }
      }
    }

    const breakdown = (type: "asset" | "liability" | "equity"): BalanceSheetLine[] =>
      Array.from(accountBalances.values()).filter(a => a.type === type && Math.abs(a.amount) >= 0.005)
        .map(a => ({ label: a.name, amount: Number(a.amount.toFixed(2)) })).sort((a, b) => b.amount - a.amount);
    const assetsBreakdown = breakdown("asset");
    const liabilitiesBreakdown = breakdown("liability");
    const equityBreakdown = [...breakdown("equity"), ...(Math.abs(lifetimeRevenue - lifetimeExpenses) >= 0.005
      ? [{ label: "Unclosed earnings from posted ledger", amount: Number((lifetimeRevenue - lifetimeExpenses).toFixed(2)) }] : [])];
    const assets = assetsBreakdown.reduce((sum, item) => sum + item.amount, 0);
    const liabilities = liabilitiesBreakdown.reduce((sum, item) => sum + item.amount, 0);
    const equity = equityBreakdown.reduce((sum, item) => sum + item.amount, 0);
    const profitLoss = Array.from(buckets.values()).map(point => ({
      ...point, revenue: Number(point.revenue.toFixed(2)), expenses: Number(point.expenses.toFixed(2)),
      netProfit: Number((point.revenue - point.expenses).toFixed(2)),
    }));
    const data: FinancialDashboardData = {
      currency: "KES", revenue: Number(revenue.toFixed(2)), expenses: Number(expenses.toFixed(2)),
      netProfit: Number((revenue - expenses).toFixed(2)), assets: Number(assets.toFixed(2)),
      liabilities: Number(liabilities.toFixed(2)), equity: Number(equity.toFixed(2)),
      profitLoss, assetsBreakdown, liabilitiesBreakdown, equityBreakdown,
    };
    if (cacheVersion) {
      // Cache writes are an optimization: a transient cache failure must not hide a valid report.
      await createSupabaseAdminClient().from("financial_report_cache").upsert({
        organization_id: organizationId,
        period_start: start,
        period_end: end,
        latest_transaction_at: cacheVersion,
        report_data: data,
      }, { onConflict: "organization_id,period_start,period_end,latest_transaction_at" });
    }
    return NextResponse.json({ data, period, start, end });
  } catch {
    return NextResponse.json({ error: "Financial ledger report could not be loaded." }, { status: 500 });
  }
}
