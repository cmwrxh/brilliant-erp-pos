export type BudgetCutTarget =
  | { kind: "amount"; value: number; currency: "KES" }
  | { kind: "payroll_percentage"; value: number };

export type OperationalSavingsLever = {
  organizationId: string;
  id: string;
  label: string;
  category: "overtime" | "contractor_spend" | "agency_spend" | "vacancy_freeze" | "process_automation" | "discretionary_spend";
  maximumMonthlySavingsKes: number;
  operationalOverlapRisk: number;
};

export type BudgetImpactSimulation = {
  targetMonthlySavingsKes: number;
  projectedMonthlySavingsKes: number;
  shortfallKes: number;
  targetMet: boolean;
  selectedLevers: Array<Pick<OperationalSavingsLever, "id" | "label" | "category" | "maximumMonthlySavingsKes" | "operationalOverlapRisk">>;
  totalOperationalOverlapRisk: number;
  notes: string[];
};

/**
 * Simulates aggregate, non-termination cost controls. It does not rank staff,
 * select roles for redundancy, or produce employee-level employment decisions.
 * Callers must authenticate the user and authorize organization membership
 * before passing tenant-scoped data into this pure calculation.
 */
export function simulateBudgetImpact(
  organizationId: string,
  monthlyPayrollKes: number,
  target: BudgetCutTarget,
  availableLevers: readonly OperationalSavingsLever[],
): BudgetImpactSimulation {
  if (!organizationId.trim()) throw new Error("organizationId is required");
  if (!Number.isFinite(monthlyPayrollKes) || monthlyPayrollKes < 0) {
    throw new Error("monthlyPayrollKes must be a finite, non-negative number");
  }
  if (!Number.isFinite(target.value) || target.value <= 0) {
    throw new Error("Target must be a positive finite number");
  }
  if (target.kind === "payroll_percentage" && target.value > 100) {
    throw new Error("Payroll percentage must not exceed 100");
  }
  if (target.kind === "amount" && target.currency !== "KES") {
    throw new Error("Only KES targets are supported");
  }

  for (const lever of availableLevers) {
    if (lever.organizationId !== organizationId) {
      throw new Error("Cross-tenant budget data rejected");
    }
    if (!lever.id.trim() || !lever.label.trim()) throw new Error("Savings lever id and label are required");
    if (!Number.isFinite(lever.maximumMonthlySavingsKes) || lever.maximumMonthlySavingsKes < 0) {
      throw new Error("Savings estimates must be finite, non-negative numbers");
    }
    if (!Number.isFinite(lever.operationalOverlapRisk) || lever.operationalOverlapRisk < 0 || lever.operationalOverlapRisk > 1) {
      throw new Error("Operational overlap risk must be between 0 and 1");
    }
  }

  const targetMonthlySavingsKes = target.kind === "amount"
    ? target.value
    : monthlyPayrollKes * (target.value / 100);

  // Exhaustive search is bounded to avoid accidental exponential work.
  if (availableLevers.length > 20) {
    throw new Error("At most 20 candidate levers may be simulated at once");
  }

  let bestMask = 0;
  let bestSavings = 0;
  let bestRisk = Number.POSITIVE_INFINITY;
  let bestOvershoot = Number.POSITIVE_INFINITY;
  const limit = 1 << availableLevers.length;

  for (let mask = 1; mask < limit; mask += 1) {
    let savings = 0;
    let risk = 0;
    for (let i = 0; i < availableLevers.length; i += 1) {
      if ((mask & (1 << i)) !== 0) {
        savings += availableLevers[i].maximumMonthlySavingsKes;
        risk += availableLevers[i].operationalOverlapRisk;
      }
    }
    if (savings < targetMonthlySavingsKes) continue;
    const overshoot = savings - targetMonthlySavingsKes;
    if (risk < bestRisk || (risk === bestRisk && overshoot < bestOvershoot)) {
      bestMask = mask;
      bestSavings = savings;
      bestRisk = risk;
      bestOvershoot = overshoot;
    }
  }

  const selectedLevers = availableLevers
    .filter((_, index) => (bestMask & (1 << index)) !== 0)
    .map(({ id, label, category, maximumMonthlySavingsKes, operationalOverlapRisk }) => ({
      id, label, category, maximumMonthlySavingsKes, operationalOverlapRisk,
    }));

  if (bestMask === 0) {
    return {
      targetMonthlySavingsKes,
      projectedMonthlySavingsKes: 0,
      shortfallKes: targetMonthlySavingsKes,
      targetMet: false,
      selectedLevers: [],
      totalOperationalOverlapRisk: 0,
      notes: ["Available non-termination savings levers cannot meet the target; review assumptions or seek human-led options."],
    };
  }

  return {
    targetMonthlySavingsKes,
    projectedMonthlySavingsKes: bestSavings,
    shortfallKes: Math.max(0, targetMonthlySavingsKes - bestSavings),
    targetMet: true,
    selectedLevers,
    totalOperationalOverlapRisk: bestRisk,
    notes: [
      "Scenario only: savings are estimates and require operational and finance review.",
      "No employee or role is scored, ranked, or selected for termination.",
      "Validate service coverage, legal obligations, and implementation costs before acting.",
    ],
  };
}
