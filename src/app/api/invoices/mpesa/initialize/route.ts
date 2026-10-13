import { createHash, randomBytes, randomUUID } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { decryptCredentials } from "@/lib/payments/crypto";
import { initializeProviderPayment } from "@/lib/payments/providers";

export const runtime = "nodejs";
export async function POST(request: NextRequest) {
  if (process.env.SAFARIPOS_INVOICE_UI_ENABLED !== "true") {
    return NextResponse.json({ error: "Invoice payment workflows remain gated pending sandbox acceptance." }, { status: 503 });
  }
  let reference = "";
  try {
    const session = await createSupabaseServerClient();
    const { data: { user } } = await session.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in before requesting invoice payment." }, { status: 401 });
    const body = await request.json() as { organizationId?: string; documentId?: string; phone?: string };
    if (!body.organizationId || !body.documentId || !body.phone) {
      return NextResponse.json({ error: "Workspace, invoice and customer phone number are required." }, { status: 400 });
    }
    const { data: membership } = await session.from("organization_members").select("role")
      .eq("organization_id", body.organizationId).eq("user_id", user.id).maybeSingle();
    if (!membership || !["owner", "admin", "manager", "cashier"].includes(membership.role)) {
      return NextResponse.json({ error: "Workspace access denied." }, { status: 403 });
    }
    const { data: invoice, error: invoiceError } = await session.from("sales_documents")
      .select("id,document_number,document_type,status,currency_code,grand_total,amount_paid,balance_due")
      .eq("organization_id", body.organizationId).eq("id", body.documentId).maybeSingle();
    if (invoiceError) throw invoiceError;
    if (!invoice || invoice.document_type !== "invoice" || ["draft", "void", "credited"].includes(invoice.status)) {
      return NextResponse.json({ error: "Only an issued invoice can request payment." }, { status: 409 });
    }
    const amount = Number(invoice.balance_due);
    if (!Number.isFinite(amount) || amount < 1 || !Number.isInteger(amount)) {
      return NextResponse.json({ error: "M-PESA STK Push requires a whole-KES outstanding balance of at least KES 1." }, { status: 409 });
    }
    const admin = createSupabaseAdminClient();
    const { data: account, error: accountError } = await admin.from("payment_provider_accounts")
      .select("encrypted_credentials,enabled,environment").eq("organization_id", body.organizationId)
      .eq("provider", "mpesa").maybeSingle();
    if (accountError) throw accountError;
    if (!account || !account.enabled || account.environment !== "test") {
      return NextResponse.json({ error: "Only a configured M-PESA sandbox account can start invoice collection. Live payments are disabled." }, { status: 409 });
    }
    const credentials = decryptCredentials(account.encrypted_credentials);
    const token = randomBytes(32).toString("hex");
    const tokenHash = createHash("sha256").update(token).digest("hex");
    reference = "ERP-" + randomUUID();
    const { error: insertError } = await admin.from("provider_transactions").insert({
      organization_id: body.organizationId, sale_id: null, document_id: invoice.id, provider: "mpesa",
      reference, amount, currency_code: invoice.currency_code, status: "pending", callback_token_hash: tokenHash
    });
    if (insertError) throw insertError;
    const base = (process.env.APP_BASE_URL ?? request.nextUrl.origin).replace(/\/$/, "");
    const callbackUrl = base + "/api/payments/webhooks/mpesa?reference=" + encodeURIComponent(reference) + "&token=" + encodeURIComponent(token);
    try {
      const initialized = await initializeProviderPayment("mpesa", credentials, {
        reference, amount, currency: invoice.currency_code, email: "invoice-payment@invalid.example",
        phone: body.phone.slice(0, 30), callbackUrl,
        metadata: { organization_id: body.organizationId, document_id: invoice.id, document_number: invoice.document_number }
      });
      if (!initialized.providerReference) throw new Error("Daraja did not return a checkout request ID.");
      const { error: updateError } = await admin.from("provider_transactions").update({
        provider_reference: initialized.providerReference, updated_at: new Date().toISOString()
      }).eq("reference", reference).eq("organization_id", body.organizationId).eq("status", "pending");
      if (updateError) throw updateError;
      return NextResponse.json({
        mobilePrompt: true,
        message: "M-PESA prompt requested. The invoice will update only after Daraja confirms payment.",
        reference, documentNumber: invoice.document_number
      }, { status: 201 });
    } catch (error) {
      await admin.from("provider_transactions").update({ status: "failed", updated_at: new Date().toISOString() })
        .eq("reference", reference).eq("organization_id", body.organizationId).eq("status", "pending");
      throw error;
    }
  } catch (error) {
    console.error("Invoice M-PESA initialization failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: error instanceof Error ? error.message : "Could not start invoice M-PESA payment." }, { status: 503 });
  }
}
