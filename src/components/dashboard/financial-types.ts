export type DashboardPeriod = "7d" | "30d" | "90d" | "ytd";

export interface DashboardKpi {
  id: string;
  label: string;
  value: number;
  currency?: string;
  deltaPercent?: number;
  trend?: number[];
}

export interface ProfitLossPoint {
  label: string;
  revenue: number;
  expenses: number;
  netProfit: number;
}

export interface BalanceSheetLine {
  label: string;
  amount: number;
}

export interface FinancialDashboardData {
  currency: string;
  revenue: number;
  expenses: number;
  netProfit: number;
  assets: number;
  liabilities: number;
  equity: number;
  profitLoss: ProfitLossPoint[];
  assetsBreakdown: BalanceSheetLine[];
  liabilitiesBreakdown: BalanceSheetLine[];
  equityBreakdown: BalanceSheetLine[];
}
