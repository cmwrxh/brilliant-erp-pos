import "server-only";

export type EtimsTaxLine = {
  itemCode: string;
  itemName: string;
  quantity: number;
  unitPrice: number;
  taxRate: number;
  taxableAmount: number;
  taxAmount: number;
};

export type EtimsSaleSnapshot = {
  organizationId: string;
  saleId: string;
  receiptNumber: string;
  currencyCode: string;
  issuedAt: string;
  subtotal: number;
  discountTotal: number;
  taxTotal: number;
  grandTotal: number;
  buyerPin?: string | null;
  items: EtimsTaxLine[];
};

export type EtimsSubmissionResult =
  | { status: "accepted"; fiscalReceiptNumber: string; signature?: string; rawResponse: unknown }
  | { status: "retry"; reason: string }
  | { status: "blocked"; reason: string };

/**
 * Fail-closed eTIMS boundary.
 *
 * KRA's current taxpayer-specific OSCU/VSCU protocol, initialization and
 * authentication requirements must be supplied and reviewed before a wire
 * serializer is enabled. Do not invent a payload or claim fiscalization based
 * on a generic HTTP response. This module intentionally never transmits while
 * the certified protocol adapter is absent.
 */
export async function submitEtimsSale(_sale: EtimsSaleSnapshot): Promise<EtimsSubmissionResult> {
  const mode = process.env.KRA_ETIMS_MODE;
  if (mode !== "sandbox" && mode !== "live") {
    return { status: "blocked", reason: "KRA_ETIMS_MODE is not configured; invoice remains queued." };
  }

  // The protocol adapter is deliberately absent until KRA supplies the
  // applicable OSCU/VSCU specification, taxpayer initialization and sandbox
  // credentials. A generic POST here could issue an invalid tax invoice.
  return {
    status: "blocked",
    reason: "KRA OSCU/VSCU protocol adapter is not certified/configured; no outbound request was sent."
  };
}
