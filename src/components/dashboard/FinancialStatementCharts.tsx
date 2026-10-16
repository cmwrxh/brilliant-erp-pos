"use client";

import { useEffect, useMemo, useState } from "react";
import type { BalanceSheetLine, DashboardPeriod, FinancialDashboardData, ProfitLossPoint } from "./financial-types";

type Props = { data: FinancialDashboardData; onPeriodChange?: (period: DashboardPeriod) => void };

const periods: { value: DashboardPeriod; label: string }[] = [
  { value: "7d", label: "7 days" },
  { value: "30d", label: "30 days" },
  { value: "90d", label: "90 days" },
  { value: "ytd", label: "Year to date" },
];

const formatMoney = (value: number, currency: string) =>
  new Intl.NumberFormat("en-KE", { style: "currency", currency, maximumFractionDigits: 0 }).format(value);

function BarChart({ points, currency }: { points: ProfitLossPoint[]; currency: string }) {
  const max = Math.max(1, ...points.flatMap((p) => [p.revenue, p.expenses]));
  return <div className="fin-chart" role="img" aria-label="Profit and loss chart showing revenue, expenses and net profit by period">
    <div className="fin-chart-legend"><span><i className="fin-dot fin-revenue" />Revenue</span><span><i className="fin-dot fin-expense" />Expenses</span><span><i className="fin-dot fin-profit" />Net profit</span></div>
    <div className="fin-bars">
      {points.map((point) => <div className="fin-bar-group" key={point.label}>
        <div className="fin-bar-pair" title={`${point.label}: revenue ${formatMoney(point.revenue, currency)}, expenses ${formatMoney(point.expenses, currency)}`}>
          <span className="fin-bar fin-bar-revenue" style={{ height: `${Math.max(2, point.revenue / max * 100)}%` }} />
          <span className="fin-bar fin-bar-expense" style={{ height: `${Math.max(2, point.expenses / max * 100)}%` }} />
        </div>
        <span className="fin-bar-label">{point.label}</span>
        <span className={`fin-profit-label ${point.netProfit < 0 ? "is-negative" : ""}`}>{formatMoney(point.netProfit, currency)}</span>
      </div>)}
    </div>
  </div>;
}

function Breakdown({ title, items, currency }: { title: string; items: BalanceSheetLine[]; currency: string }) {
  const total = items.reduce((sum, item) => sum + item.amount, 0);
  return <section className="fin-breakdown">
    <h3>{title}</h3>
    {items.map((item) => <div className="fin-breakdown-row" key={item.label}>
      <span>{item.label}</span><strong>{formatMoney(item.amount, currency)}</strong>
      <div className="fin-track"><span style={{ width: `${total > 0 ? Math.min(100, Math.max(0, item.amount / total * 100)) : 0}%` }} /></div>
    </div>)}
    <div className="fin-breakdown-total"><span>Total</span><strong>{formatMoney(total, currency)}</strong></div>
  </section>;
}

export function FinancialStatementCharts({ data, onPeriodChange }: Props) {
  const [period, setPeriod] = useState<DashboardPeriod>("30d");
  const [statement, setStatement] = useState<"pnl" | "balance">("pnl");
  const [displayData, setDisplayData] = useState<FinancialDashboardData>(data);
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [loading, setLoading] = useState(false);
  const [reportError, setReportError] = useState<string | null>(null);

  useEffect(() => {
    if ((startDate && !endDate) || (!startDate && endDate)) return;
    const controller = new AbortController();
    const params = new URLSearchParams({ period });
    if (startDate && endDate) {
      params.set("start", startDate);
      params.set("end", endDate);
    }
    setLoading(true);
    setReportError(null);
    fetch(`/api/reports/financial?${params.toString()}`, {
      method: "GET", credentials: "same-origin", cache: "no-store", signal: controller.signal,
    }).then(async (response) => {
      const result: { data?: FinancialDashboardData; error?: string } = await response.json();
      if (!response.ok || !result.data) throw new Error(result.error ?? "Could not refresh financial report.");
      setDisplayData(result.data);
    }).catch((error: unknown) => {
      if (error instanceof Error && error.name === "AbortError") return;
      setReportError(error instanceof Error ? error.message : "Could not refresh financial report.");
    }).finally(() => {
      if (!controller.signal.aborted) setLoading(false);
    });
    return () => controller.abort();
  }, [period, startDate, endDate]);

  const balanced = Math.abs(displayData.assets - (displayData.liabilities + displayData.equity)) < 0.01;
  const netMargin = displayData.revenue > 0 ? displayData.netProfit / displayData.revenue * 100 : 0;
  const chartPoints = useMemo(() => displayData.profitLoss, [displayData.profitLoss]);

  function changePeriod(next: DashboardPeriod) {
    setPeriod(next);
    onPeriodChange?.(next);
  }

  return <section className="financial-statements" aria-label="Financial statement visualizations">
    <div className="fin-section-heading">
      <div><p className="fin-eyebrow">FINANCIAL PERFORMANCE</p><h2>Financial overview</h2><p>Management view · {displayData.currency}</p></div>
      <div className="fin-periods" aria-label="Reporting period">
        {periods.map((item) => <button key={item.value} type="button" aria-pressed={period === item.value} className={period === item.value ? "is-active" : ""} onClick={() => { setStartDate(""); setEndDate(""); changePeriod(item.value); }}>{item.label}</button>)}
      </div>
      <div className="fin-custom-range" aria-label="Custom reporting date range">
        <label>From <input type="date" aria-label="Reporting start date" value={startDate} max={endDate || undefined} onChange={(event) => setStartDate(event.target.value)} /></label>
        <label>To <input type="date" aria-label="Reporting end date" value={endDate} min={startDate || undefined} max={new Date().toISOString().slice(0, 10)} onChange={(event) => setEndDate(event.target.value)} /></label>
      </div>
    </div>
    {reportError && <div className="fin-balance-alert" role="alert">{reportError}</div>}
    {loading && <p className="fin-loading" role="status">Refreshing ledger report…</p>}
    {!balanced && <div className="fin-balance-alert" role="alert" aria-live="assertive"><strong>Balance Sheet out of balance</strong><span>Assets differ from liabilities plus equity by {formatMoney(Math.abs(displayData.assets - (displayData.liabilities + displayData.equity)), displayData.currency)}. Review posted journals before relying on this statement.</span></div>}
    <div className="fin-summary-grid">
      <article><span>Revenue</span><strong>{formatMoney(displayData.revenue, displayData.currency)}</strong></article>
      <article><span>Expenses</span><strong>{formatMoney(displayData.expenses, displayData.currency)}</strong></article>
      <article><span>Net profit</span><strong className={displayData.netProfit < 0 ? "is-negative" : "is-positive"}>{formatMoney(displayData.netProfit, displayData.currency)}</strong><small>{netMargin.toFixed(1)}% net margin</small></article>
    </div>
    <div className="fin-tabs" role="tablist" aria-label="Financial statements">
      <button type="button" role="tab" aria-selected={statement === "pnl"} className={statement === "pnl" ? "is-active" : ""} onClick={() => setStatement("pnl")}>Profit &amp; Loss</button>
      <button type="button" role="tab" aria-selected={statement === "balance"} className={statement === "balance" ? "is-active" : ""} onClick={() => setStatement("balance")}>Balance Sheet</button>
    </div>
    {statement === "pnl" ? <div className="fin-panel"><div className="fin-panel-heading"><div><h3>Profit &amp; Loss</h3><p>Revenue compared with expenses and net profit</p></div><span className="fin-period-chip">{periods.find((p) => p.value === period)?.label}</span></div><BarChart points={chartPoints} currency={displayData.currency} /></div> :
      <div className="fin-panel"><div className="fin-panel-heading"><div><h3>Balance Sheet</h3><p>Assets = liabilities + equity</p></div><span className={`fin-balance-status ${balanced ? "is-balanced" : "is-unbalanced"}`}>{balanced ? "Balances" : "Out of balance"}</span></div>
        <div className="fin-balance-equation"><div><span>Total assets</span><strong>{formatMoney(displayData.assets, displayData.currency)}</strong></div><span className="fin-equation-sign">=</span><div><span>Liabilities + equity</span><strong>{formatMoney(displayData.liabilities + displayData.equity, displayData.currency)}</strong></div></div>
        <div className="fin-breakdown-grid"><Breakdown title="Assets" items={displayData.assetsBreakdown} currency={displayData.currency} /><Breakdown title="Liabilities" items={displayData.liabilitiesBreakdown} currency={displayData.currency} /><Breakdown title="Equity" items={displayData.equityBreakdown} currency={displayData.currency} /></div>
      </div>}
    <p className="fin-disclaimer">Presentation layer only. Displayed values must be supplied by accepted, organization-scoped accounting reports; this component does not calculate or certify posted financial statements.</p>
  </section>;
}
