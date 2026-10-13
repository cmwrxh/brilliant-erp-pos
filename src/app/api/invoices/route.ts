import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "node:crypto";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
const enabled = () => process.env.SAFARIPOS_INVOICE_UI_ENABLED === "true";

export async function GET(request: NextRequest) {
  if (!enabled()) return NextResponse.json({ error: "Invoice workflows are gated pending M-PESA/eTIMS sandbox acceptance." }, { status: 503 });
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in to view invoices." }, { status: 401 });
    const organizationId = request.nextUrl.searchParams.get("organizationId");
    if (!organizationId) return NextResponse.json({ error: "Select a workspace." }, { status: 400 });
    const { data: membership } = await supabase.from("organization_members").select("role").eq("organization_id", organizationId).eq("user_id", user.id).maybeSingle();
    if (!membership) return NextResponse.json({ error: "Workspace access denied." }, { status: 403 });
    const { data, error } = await supabase.from("sales_documents")
      .select("id,document_number,document_type,status,customer_id,location_id,currency_code,subtotal,discount_total,tax_total,grand_total,amount_paid,balance_due,issued_at,due_at,created_at")
      .eq("organization_id", organizationId).eq("document_type", "invoice")
      .order("created_at", { ascending: false }).limit(250);
    if (error) throw error;
    return NextResponse.json({ invoices: data ?? [] });
  } catch (error) {
    console.error("Invoice list failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Invoice list could not be loaded. Confirm the reviewed database migrations are installed." }, { status: 503 });
  }
}

export async function POST(request: NextRequest) {
  if (!enabled()) return NextResponse.json({ error: "Invoice workflows are gated pending M-PESA/eTIMS sandbox acceptance." }, { status: 503 });
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in to create an invoice." }, { status: 401 });
    const body = await request.json() as {
      organizationId?: string; documentNumber?: string; customerId?: string; locationId?: string;
      dueAt?: string; idempotencyKey?: string;
      items?: { productId: string; quantity: number; discountAmount?: number }[];
    };
    if (!body.organizationId || !body.documentNumber?.trim() || !body.customerId || !body.locationId ||
        !body.dueAt || !Array.isArray(body.items) || body.items.length < 1 || body.items.length > 200) {
      return NextResponse.json({ error: "Invoice number, customer, branch, due date and 1–200 items are required." }, { status: 400 });
    }
    const items = body.items.map(item => ({
      product_id: String(item.productId ?? ""),
      quantity: Number(item.quantity),
      discount_amount: Number(item.discountAmount ?? 0)
    }));
    if (items.some(item => !item.product_id || !Number.isFinite(item.quantity) || item.quantity <= 0 ||
      !Number.isFinite(item.discount_amount) || item.discount_amount < 0)) {
      return NextResponse.json({ error: "Check the product quantities and discounts." }, { status: 400 });
    }
    const { data: membership } = await supabase.from("organization_members").select("role")
      .eq("organization_id", body.organizationId).eq("user_id", user.id).maybeSingle();
    if (!membership || !["owner", "admin", "manager"].includes(membership.role)) {
      return NextResponse.json({ error: "Only workspace owners, admins or managers can create invoice drafts." }, { status: 403 });
    }
    const { data: invoiceId, error } = await supabase.rpc("create_sales_invoice_draft", {
      p_organization_id: body.organizationId,
      p_document_number: body.documentNumber.trim(),
      p_customer_id: body.customerId,
      p_location_id: body.locationId,
      p_due_at: body.dueAt,
      p_lines: items,
      p_idempotency_key: body.idempotencyKey ?? randomUUID()
    });
    if (error) {
      if (error.code === "23505") return NextResponse.json({ error: "That invoice number or idempotency key already exists." }, { status: 409 });
      if (error.code === "42501") return NextResponse.json({ error: "You do not have permission to create invoices." }, { status: 403 });
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ invoiceId }, { status: 201 });
  } catch (error) {
    console.error("Invoice draft creation failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Invoice draft could not be created." }, { status: 503 });
  }
}
