export type WorkforceMetricObservation = {
  organizationId: string;
  employeeId: string;
  role: string;
  level: string;
  period: string;
  salesThroughput: number;
  inventoryThroughput: number;
};

export type NormalizedPeerGroup = {
  role: string;
  level: string;
  employeeCount: number;
  periodCount: number;
  averageSalesThroughput: number;
  averageInventoryThroughput: number;
  averageCombinedThroughput: number;
  salesThroughputStdDev: number;
  inventoryThroughputStdDev: number;
};

/**
 * Tenant-scoped, aggregate-only peer normalization. Employee identifiers are
 * used only to avoid over-weighting people with more history; they are never
 * returned and no individual score or ranking is generated.
 */
export function normalizePeerGroups(
  organizationId: string,
  observations: readonly WorkforceMetricObservation[],
  minimumCohortSize = 3,
): NormalizedPeerGroup[] {
  if (!organizationId.trim()) throw new Error("organizationId is required");
  if (!Number.isInteger(minimumCohortSize) || minimumCohortSize < 3) {
    throw new Error("minimumCohortSize must be an integer of at least 3");
  }

  const cohorts = new Map<string, WorkforceMetricObservation[]>();
  for (const observation of observations) {
    if (observation.organizationId !== organizationId) {
      throw new Error("Cross-tenant workforce data rejected");
    }
    if (!observation.employeeId.trim() || !observation.role.trim() || !observation.level.trim() || !observation.period.trim()) {
      throw new Error("Employee, role, level, and period are required");
    }
    for (const value of [observation.salesThroughput, observation.inventoryThroughput]) {
      if (!Number.isFinite(value) || value < 0) {
        throw new Error("Throughput metrics must be finite, non-negative numbers");
      }
    }

    const key = JSON.stringify([observation.role.trim().toLowerCase(), observation.level.trim().toLowerCase()]);
    const cohort = cohorts.get(key) ?? [];
    cohort.push(observation);
    cohorts.set(key, cohort);
  }

  const mean = (values: number[]) => values.reduce((sum, value) => sum + value, 0) / values.length;
  const stdDev = (values: number[], average: number) =>
    Math.sqrt(values.reduce((sum, value) => sum + (value - average) ** 2, 0) / values.length);

  return [...cohorts.values()].flatMap((cohort) => {
    const byEmployee = new Map<string, WorkforceMetricObservation[]>();
    for (const item of cohort) {
      const history = byEmployee.get(item.employeeId) ?? [];
      history.push(item);
      byEmployee.set(item.employeeId, history);
    }
    if (byEmployee.size < minimumCohortSize) return [];

    const employeeMeans = [...byEmployee.values()].map((history) => ({
      sales: mean(history.map((item) => item.salesThroughput)),
      inventory: mean(history.map((item) => item.inventoryThroughput)),
    }));
    const sales = employeeMeans.map((item) => item.sales);
    const inventory = employeeMeans.map((item) => item.inventory);
    const averageSales = mean(sales);
    const averageInventory = mean(inventory);

    return [{
      role: cohort[0].role.trim(),
      level: cohort[0].level.trim(),
      employeeCount: byEmployee.size,
      periodCount: new Set(cohort.map((item) => item.period)).size,
      averageSalesThroughput: averageSales,
      averageInventoryThroughput: averageInventory,
      averageCombinedThroughput: averageSales + averageInventory,
      salesThroughputStdDev: stdDev(sales, averageSales),
      inventoryThroughputStdDev: stdDev(inventory, averageInventory),
    }];
  }).sort((a, b) => a.role.localeCompare(b.role) || a.level.localeCompare(b.level));
}
