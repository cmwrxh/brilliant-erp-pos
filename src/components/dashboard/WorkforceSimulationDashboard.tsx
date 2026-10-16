"use client";

import { useMemo, useState } from "react";
import {
  normalizePeerGroups,
  type WorkforceMetricObservation,
} from "@/lib/efficiency/normalization";
import {
  simulateBudgetImpact,
  type OperationalSavingsLever,
} from "@/lib/efficiency/simulator";

type WorkforceSimulationDashboardProps = {
  organizationId: string;
  monthlyPayrollKes: number;
  observations: readonly WorkforceMetricObservation[];
  savingsLevers: readonly OperationalSavingsLever[];
};

const MINIMUM_COHORT_SIZE = 3;

const kes = (value: number) =>
  new Intl.NumberFormat("en-KE", {
    style: "currency",
    currency: "KES",
    maximumFractionDigits: 0,
  }).format(value);

export default function WorkforceSimulationDashboard({
  organizationId,
  monthlyPayrollKes,
  observations,
  savingsLevers,
}: WorkforceSimulationDashboardProps) {
  const [targetPercentage, setTargetPercentage] = useState(10);
  const [selectedRole, setSelectedRole] = useState("all");

  const availableRoles = useMemo(() => {
    const roles = new Map<string, string>();
    for (const observation of observations) {
      if (observation.organizationId !== organizationId) continue;
      const role = observation.role.trim();
      if (role) roles.set(role.toLocaleLowerCase(), role);
    }
    return [...roles.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, label]) => ({ key, label }));
  }, [organizationId, observations]);

  const roleObservations = useMemo(
    () => selectedRole === "all"
      ? observations
      : observations.filter((observation) =>
          observation.organizationId === organizationId &&
          observation.role.trim().toLocaleLowerCase() === selectedRole),
    [organizationId, observations, selectedRole],
  );

  const selectedRoleEmployeeCount = useMemo(() => {
    if (selectedRole === "all") return null;
    return new Set(
      roleObservations
        .filter((observation) => observation.organizationId === organizationId)
        .map((observation) => observation.employeeId.trim())
        .filter(Boolean),
    ).size;
  }, [organizationId, roleObservations, selectedRole]);

  const result = useMemo(() => {
    try {
      const peerGroups = normalizePeerGroups(organizationId, roleObservations, MINIMUM_COHORT_SIZE);
      const simulation = simulateBudgetImpact(
        organizationId,
        monthlyPayrollKes,
        { kind: "payroll_percentage", value: targetPercentage },
        savingsLevers,
      );
      return { peerGroups, simulation, error: null };
    } catch (cause) {
      return {
        peerGroups: [],
        simulation: null,
        error: cause instanceof Error ? cause.message : "Unable to calculate this scenario.",
      };
    }
  }, [organizationId, monthlyPayrollKes, roleObservations, savingsLevers, targetPercentage]);

  const maximumThroughput = Math.max(
    1,
    ...result.peerGroups.map((group) => Math.max(group.averageSalesThroughput, group.averageInventoryThroughput)),
  );
  const roleBelowPrivacyThreshold = selectedRoleEmployeeCount !== null &&
    selectedRoleEmployeeCount < MINIMUM_COHORT_SIZE;

  return (
    <section className="space-y-6" aria-labelledby="workforce-simulation-title">
      <header>
        <h2 id="workforce-simulation-title" className="text-xl font-semibold">
          Workforce &amp; operating-cost insights
        </h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Aggregate peer-group trends and non-termination cost scenarios. Individual employee scores and rankings are never displayed.
        </p>
      </header>

      <div className="rounded-xl border p-5 space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <label htmlFor="payroll-savings-target" className="font-medium">
            Reduce payroll by
          </label>
          <output htmlFor="payroll-savings-target" className="text-lg font-semibold tabular-nums">
            {targetPercentage}%
          </output>
        </div>
        <input
          id="payroll-savings-target"
          type="range"
          min={1}
          max={30}
          step={1}
          value={targetPercentage}
          onChange={(event) => setTargetPercentage(Number(event.currentTarget.value))}
          className="w-full accent-primary"
          aria-describedby="payroll-savings-help"
        />
        <div className="flex justify-between text-xs text-muted-foreground">
          <span>1%</span>
          <span>30%</span>
        </div>
        <p id="payroll-savings-help" className="text-sm text-muted-foreground">
          The shared budget optimization engine recalculates this scenario as the target changes. Estimates are not employment recommendations.
        </p>

        {result.error ? (
          <p role="alert" className="text-sm text-destructive">{result.error}</p>
        ) : result.simulation ? (
          <div className="grid gap-3 sm:grid-cols-3">
            <Metric label="Target savings" value={kes(result.simulation.targetMonthlySavingsKes)} />
            <Metric label="Projected savings" value={kes(result.simulation.projectedMonthlySavingsKes)} />
            <Metric label="Remaining shortfall" value={kes(result.simulation.shortfallKes)} />
          </div>
        ) : null}

        {result.simulation && (
          <div className="space-y-2">
            <p className="text-sm font-medium">
              {result.simulation.targetMet ? "Scenario target can be met by the selected levers" : "Available levers do not meet the target"}
            </p>
            {result.simulation.selectedLevers.length ? (
              <ul className="divide-y rounded-lg border">
                {result.simulation.selectedLevers.map((lever) => (
                  <li key={lever.id} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-sm">
                    <span>{lever.label}</span>
                    <span className="tabular-nums">{kes(lever.maximumMonthlySavingsKes)} / month</span>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="text-sm text-muted-foreground">Review the available cost assumptions; no suitable combination was found.</p>
            )}
            <ul className="list-disc space-y-1 pl-5 text-xs text-muted-foreground">
              {result.simulation.notes.map((note) => <li key={note}>{note}</li>)}
            </ul>
          </div>
        )}
      </div>

      <div className="rounded-xl border p-5 space-y-4">
        <div>
          <h3 className="font-semibold">Peer-group throughput averages</h3>
          <p className="mt-1 text-sm text-muted-foreground">
            Role-and-level cohorts with at least three distinct people. Bars show cohort averages only, never individual performance.
          </p>
        </div>

        <div className="space-y-2">
          <label htmlFor="workforce-role-filter" className="text-sm font-medium">Filter by role</label>
          <select
            id="workforce-role-filter"
            value={selectedRole}
            onChange={(event) => setSelectedRole(event.currentTarget.value)}
            className="w-full rounded-lg border bg-background px-3 py-2 text-sm sm:max-w-sm"
          >
            <option value="all">All eligible roles</option>
            {availableRoles.map((role) => (
              <option key={role.key} value={role.key}>{role.label}</option>
            ))}
          </select>
        </div>

        {result.error ? (
          <p role="alert" className="text-sm text-destructive">{result.error}</p>
        ) : roleBelowPrivacyThreshold ? (
          <div className="rounded-lg border border-amber-500/40 bg-amber-500/5 p-4 text-sm" role="status" aria-live="polite">
            <p className="font-semibold">Privacy safeguard active</p>
            <p className="mt-1 text-muted-foreground">
              This role has fewer than {MINIMUM_COHORT_SIZE} distinct employees. Performance charts are hidden to protect employee privacy. Broaden the filter to view eligible aggregate cohorts.
            </p>
          </div>
        ) : result.peerGroups.length === 0 ? (
          <p className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground">
            No eligible peer groups for this filter. Role-and-level cohorts must contain at least {MINIMUM_COHORT_SIZE} distinct employees before aggregate metrics can be shown.
          </p>
        ) : (
          <div className="space-y-5">
            {result.peerGroups.map((group) => (
              <div key={group.role.toLocaleLowerCase() + ":" + group.level.toLocaleLowerCase()} className="space-y-2">
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <p className="font-medium">{group.role} · {group.level}</p>
                  <p className="text-xs text-muted-foreground">
                    {group.employeeCount} people · {group.periodCount} periods
                  </p>
                </div>
                <Bar label="Sales cohort average" value={group.averageSalesThroughput} maximum={maximumThroughput} />
                <Bar label="Inventory cohort average" value={group.averageInventoryThroughput} maximum={maximumThroughput} />
                <p className="text-xs text-muted-foreground">
                  Combined cohort average: {group.averageCombinedThroughput.toLocaleString()}
                </p>
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg bg-muted/40 p-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-1 text-lg font-semibold tabular-nums">{value}</p>
    </div>
  );
}

function Bar({ label, value, maximum }: { label: string; value: number; maximum: number }) {
  const width = Math.max(0, Math.min(100, (value / maximum) * 100));
  return (
    <div className="space-y-1">
      <div className="flex justify-between gap-3 text-xs">
        <span>{label}</span>
        <span className="tabular-nums">{value.toLocaleString(undefined, { maximumFractionDigits: 2 })}</span>
      </div>
      <div
        className="h-2.5 overflow-hidden rounded-full bg-muted"
        role="img"
        aria-label={label + ": " + value.toLocaleString()}
      >
        <div className="h-full rounded-full bg-primary" style={{ width: width + "%" }} />
      </div>
    </div>
  );
}
