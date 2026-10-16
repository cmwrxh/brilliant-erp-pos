"use client";

import type { ReactNode } from "react";
import type { DashboardKpi } from "./financial-types";

type Props = {
  organizationName: string;
  periodLabel?: string;
  kpis: DashboardKpi[];
  children?: ReactNode;
};

const money = (value: number, currency = "KES") =>
  new Intl.NumberFormat("en-KE", { style: "currency", currency, maximumFractionDigits: 0 }).format(value);

export function CorporateDashboardFrame({ organizationName, periodLabel = "Current reporting period", kpis, children }: Props) {
  return <main className="corporate-dashboard-frame">
    <header className="corp-heading">
      <div><p className="corp-eyebrow">SAFARIPOS · CORPORATE</p><h1>Business overview</h1><p>{organizationName} · {periodLabel}</p></div>
      <span className="corp-live-tag"><i aria-hidden="true" /> Financial data status depends on connected reporting source</span>
    </header>
    <section className="corp-kpi-grid" aria-label="Key business indicators">
      {kpis.map((kpi) => <article className="corp-kpi" key={kpi.id}>
        <span>{kpi.label}</span>
        <strong>{money(kpi.value, kpi.currency ?? "KES")}</strong>
        <small>{kpi.deltaPercent === undefined ? "Reporting period total" : `${kpi.deltaPercent >= 0 ? "+" : ""}${kpi.deltaPercent.toFixed(1)}% vs previous period`}</small>
      </article>)}
    </section>
    {children}
  </main>;
}
