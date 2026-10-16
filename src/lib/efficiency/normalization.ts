export type WorkforceMetricObservation = {
  organizationId: string;
  role: string;
  level: string;
  period: string;
  salesThroughput: number;
  inventoryThroughput: number;
};

export type NormalizedPeerGroup = {
  role: string;
  level: string;
  observationCount: number;
  periodCount: number;
  averageSalesThroughput: number;
  averageInventoryThroughput: number;
  averageCombinedThroughput: number;
  salesThroughputStdDev: number;
  inventoryThroughputStdDev: number;
};

/**
 * Tenant-scoped, aggregate-only peer normalization.
 *
 * Deliberately returns cohort statistics rather than employee-level scores or
 * rankings. Use a minimum cohort size to reduce re-identification risk.
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
    if (!observation.role.trim() || !observation.level.trim() || !observation.period.trim()) {
      throw new Error("Role, level, and period are required");
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

  return [...cohorts.values()]
    .filter((cohort) => new Set(cohort.map((item) => item.period)).size >= minimumCohortSize)
    .map((cohort) => {
      const sales = cohort.map((item) => item.salesThroughput);
      const inventory = cohort.map((item) => item.inventoryThroughput);
      const averageSales = mean(sales);
      const averageInventory = mean(inventory);
      return {
        role: cohort[0].role.trim(),
        level: cohort[0].level.trim(),
        observationCount: cohort.length,
        periodCount: new Set(cohort.map((item) => item.period)).size,
        averageSalesThroughput: averageSales,
        averageInventoryThroughput: averageInventory,
        averageCombinedThroughput: averageSales + averageInventory,
        salesThroughputStdDev: stdDev(sales, averageSales),
        inventoryThroughputStdDev: stdDev(inventory, averageInventory),
      };
    })
    .sort((a, b) => a.role.localeCompare(b.role) || a.level.localeCompare(b.level));
}
