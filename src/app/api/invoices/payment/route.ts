import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "node:crypto";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export async function POST(request: NextRequest) {
  if (process.env.SAFARIPOS_INVOICE_UI_ENABLED !== "true") {
    return NextResponse.json({ error: "Invoice payment workflows remain gated pending sandbox acceptance." }, { status: 503 });
  }
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in to record an invoice payment." }, { status: 401 });
    const body = await request.json() as { organizationId?: string; documentId?: string; tenderType?: string; amount?: number; providerReference?: string; idempotencyKey?: string };
    if (!body.organizationId || !body.documentId || !body.tenderType || !Number.isFinite(Number(body.amount)) || Number(body.amount) <= 0) {
      return NextResponse.json({ error: "Workspace, invoice, tender and positive amount are required." }, { status: 400 });
    }
    if (!["cash", "bank_transfer", "card", "other"].includes(body.tenderType)) {
      return NextResponse.json({ error: "M-PESA cannot be manually marked successful. Use the verified STK callback flow." }, { status: 400 });
    }
    const { data: membership } = await supabase.from("organization_members").select("role")
      .eq("organization_id", body.organizationId).eq("user_id", user.id).maybeSingle();
    if (!membership || !["owner", "admin", "manager", "cashier"].includes(membership.role)) {
      return NextResponse.json({ error: "Workspace access denied." }, { status: 403 });
    }
    const idempotencyKey = body.idempotencyKey?.trim() || ("invoice-manual:" + randomUUID());
    if (idempotencyKey.length < 8 || idempotencyKey.length > 160) return NextResponse.json({ error: "Invalid payment idempotency key." }, { status: 400 });
    const { data, error } = await supabase.rpc("record_document_payment", {
      p_organization_id: body.organizationId,
      p_document_id: body.documentId,
      p_tender_type: body.tenderType,
      p_amount: Number(body.amount),
      p_idempotency_key: idempotencyKey,
      p_provider: null,
      p_provider_reference: body.providerReference?.trim() || null
    });
    if (error) {
      if (error.code === "23514") return NextResponse.json({ error: error.message }, { status: 409 });
      if (error.code === "42501") return NextResponse.json({ error: error.message }, { status: 403 });
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ paymentId: data }, { status: 201 });
  } catch (error) {
    console.error("Manual invoice payment failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Could not record invoice payment." }, { status: 503 });
  }
}
