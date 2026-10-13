import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  if (process.env.SAFARIPOS_INVOICE_UI_ENABLED !== "true") {
    return NextResponse.json({ error: "Invoice workflows are gated pending M-PESA/eTIMS sandbox acceptance." }, { status: 503 });
  }
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in to issue an invoice." }, { status: 401 });
    const body = await request.json() as { organizationId?: string; documentId?: string };
    if (!body.organizationId || !body.documentId) return NextResponse.json({ error: "Workspace and invoice are required." }, { status: 400 });
    const { data: membership } = await supabase.from("organization_members").select("role")
      .eq("organization_id", body.organizationId).eq("user_id", user.id).maybeSingle();
    if (!membership || !["owner", "admin", "manager"].includes(membership.role)) {
      return NextResponse.json({ error: "Only workspace owners, admins or managers can issue invoices." }, { status: 403 });
    }
    const { data, error } = await supabase.rpc("issue_sales_invoice", {
      p_organization_id: body.organizationId,
      p_document_id: body.documentId
    });
    if (error) {
      if (error.code === "42501") return NextResponse.json({ error: "You do not have permission to issue invoices." }, { status: 403 });
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ invoiceId: data, status: "issued", etimsStatus: "queued_not_submitted" });
  } catch (error) {
    console.error("Invoice issue failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Invoice could not be issued." }, { status: 503 });
  }
}
