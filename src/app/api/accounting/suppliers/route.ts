import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
export const runtime = "nodejs";
const enabled = () => process.env.SAFARIPOS_ACCOUNTING_WORKFLOWS_ENABLED === "true";

export async function GET(request: NextRequest) {
  if (!enabled()) return NextResponse.json({ error: "Accounting workflows remain gated pending acceptance." }, { status: 503 });
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in to view supplier accounts." }, { status: 401 });
    const organizationId = request.nextUrl.searchParams.get("organizationId");
    if (!organizationId) return NextResponse.json({ error: "Workspace is required." }, { status: 400 });
    const { data: membership } = await supabase.from("organization_members").select("role").eq("organization_id", organizationId).eq("user_id", user.id).maybeSingle();
    if (!membership) return NextResponse.json({ error: "Workspace access denied." }, { status: 403 });
    const [supplierResult, billResult] = await Promise.all([
      supabase.from("suppliers").select("id,name,supplier_code,kra_pin,phone,email,is_active").eq("organization_id", organizationId).order("name").limit(1000),
      supabase.from("supplier_bills").select("id,supplier_id,supplier_invoice_number,bill_date,due_date,status,subtotal,input_tax,total_amount,amount_paid,created_at").eq("organization_id", organizationId).order("bill_date", { ascending: false }).limit(500)
    ]);
    if (supplierResult.error) throw supplierResult.error;
    if (billResult.error) throw billResult.error;
    return NextResponse.json({ suppliers: supplierResult.data ?? [], bills: billResult.data ?? [] });
  } catch (error) {
    console.error("Supplier account load failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Supplier accounts could not be loaded. Confirm migrations are installed." }, { status: 503 });
  }
}

export async function POST(request: NextRequest) {
  if (!enabled()) return NextResponse.json({ error: "Accounting workflows remain gated pending acceptance." }, { status: 503 });
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in to update supplier accounts." }, { status: 401 });
    const body = await request.json() as {
      organizationId?: string; action?: string; name?: string; supplierCode?: string; kraPin?: string; phone?: string; email?: string;
      supplierId?: string; invoiceNumber?: string; billDate?: string; dueDate?: string; idempotencyKey?: string;
      lines?: { description: string; account_code: string; net_amount: number; tax_amount?: number }[];
      billId?: string; tenderType?: string; amount?: number; providerReference?: string;
    };
    if (!body.organizationId || !body.action) return NextResponse.json({ error: "Workspace and action are required." }, { status: 400 });
    const { data: membership } = await supabase.from("organization_members").select("role").eq("organization_id", body.organizationId).eq("user_id", user.id).maybeSingle();
    if (!membership || !["owner", "admin", "manager"].includes(membership.role)) return NextResponse.json({ error: "Only owners, admins or managers can manage supplier accounts." }, { status: 403 });
    let rpcName = "";
    let args: Record<string, unknown> = { p_organization_id: body.organizationId };
    if (body.action === "create_supplier") {
      if (!body.name?.trim()) return NextResponse.json({ error: "Supplier name is required." }, { status: 400 });
      rpcName = "create_supplier";
      args = { ...args, p_name: body.name.trim(), p_supplier_code: body.supplierCode ?? null, p_kra_pin: body.kraPin ?? null, p_phone: body.phone ?? null, p_email: body.email ?? null };
    } else if (body.action === "create_bill") {
      if (!body.supplierId || !body.invoiceNumber?.trim() || !body.billDate || !Array.isArray(body.lines) || !body.lines.length) return NextResponse.json({ error: "Supplier, invoice number, bill date and at least one line are required." }, { status: 400 });
      rpcName = "create_supplier_bill";
      args = { ...args, p_supplier_id: body.supplierId, p_supplier_invoice_number: body.invoiceNumber.trim(), p_bill_date: body.billDate, p_due_date: body.dueDate || null, p_lines: body.lines, p_idempotency_key: body.idempotencyKey || crypto.randomUUID() };
    } else if (body.action === "pay_bill") {
      if (!body.billId || !body.tenderType || !Number.isFinite(Number(body.amount)) || Number(body.amount) <= 0) return NextResponse.json({ error: "Bill, tender and positive payment amount are required." }, { status: 400 });
      rpcName = "record_supplier_bill_payment";
      args = { ...args, p_bill_id: body.billId, p_tender_type: body.tenderType, p_amount: Number(body.amount), p_idempotency_key: body.idempotencyKey || crypto.randomUUID(), p_provider_reference: body.providerReference ?? null };
    } else {
      return NextResponse.json({ error: "Unsupported supplier action." }, { status: 400 });
    }
    const { data, error } = await supabase.rpc(rpcName, args);
    if (error) return NextResponse.json({ error: error.message }, { status: error.code === "42501" ? 403 : error.code === "23505" ? 409 : 400 });
    return NextResponse.json({ id: data }, { status: 201 });
  } catch (error) {
    console.error("Supplier action failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Supplier action could not be completed." }, { status: 503 });
  }
}
