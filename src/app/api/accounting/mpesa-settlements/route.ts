import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
export const runtime = "nodejs";
const enabled = () => process.env.SAFARIPOS_ACCOUNTING_WORKFLOWS_ENABLED === "true";

export async function GET(request: NextRequest) {
  if (!enabled()) return NextResponse.json({ error: "Accounting workflows remain gated pending acceptance." }, { status: 503 });
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in to view settlements." }, { status: 401 });
    const organizationId = request.nextUrl.searchParams.get("organizationId");
    if (!organizationId) return NextResponse.json({ error: "Workspace is required." }, { status: 400 });
    const { data: membership } = await supabase.from("organization_members").select("role").eq("organization_id", organizationId).eq("user_id", user.id).maybeSingle();
    if (!membership) return NextResponse.json({ error: "Workspace access denied." }, { status: 403 });
    const [settlementResult, paymentResult, matchResult] = await Promise.all([
      supabase.from("mpesa_settlements").select("id,settlement_reference,period_start,period_end,gross_amount,fee_amount,net_amount,bank_reference,status,journal_entry_id,created_at").eq("organization_id", organizationId).order("period_end", { ascending: false }).limit(250),
      supabase.from("document_payments").select("id,document_id,provider_reference,amount,received_amount,confirmed_at,status").eq("organization_id", organizationId).eq("tender_type", "mpesa").eq("status", "succeeded").order("confirmed_at", { ascending: false }).limit(1000),
      supabase.from("mpesa_settlement_matches").select("payment_id,settlement_id").eq("organization_id", organizationId)
    ]);
    if (settlementResult.error) throw settlementResult.error;
    if (paymentResult.error) throw paymentResult.error;
    if (matchResult.error) throw matchResult.error;
    const matched = new Set((matchResult.data ?? []).map(x => x.payment_id));
    return NextResponse.json({ settlements: settlementResult.data ?? [], payments: (paymentResult.data ?? []).filter(x => !matched.has(x.id)) });
  } catch (error) {
    console.error("Settlement load failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Settlement data could not be loaded." }, { status: 503 });
  }
}

export async function POST(request: NextRequest) {
  if (!enabled()) return NextResponse.json({ error: "Accounting workflows remain gated pending acceptance." }, { status: 503 });
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in to reconcile settlements." }, { status: 401 });
    const body = await request.json() as {
      organizationId?: string; action?: string; settlementId?: string; paymentIds?: string[];
      settlementReference?: string; periodStart?: string; periodEnd?: string; grossAmount?: number; feeAmount?: number; netAmount?: number; bankReference?: string;
    };
    if (!body.organizationId || !body.action) return NextResponse.json({ error: "Workspace and action are required." }, { status: 400 });
    const { data: membership } = await supabase.from("organization_members").select("role").eq("organization_id", body.organizationId).eq("user_id", user.id).maybeSingle();
    if (!membership || !["owner", "admin", "manager"].includes(membership.role)) return NextResponse.json({ error: "Only owners, admins or managers can reconcile settlements." }, { status: 403 });
    let rpcName: string;
    let args: Record<string, unknown>;
    if (body.action === "record") {
      if (!body.settlementReference?.trim() || !body.periodStart || !body.periodEnd || !Number.isFinite(Number(body.grossAmount)) || !Number.isFinite(Number(body.feeAmount)) || !Number.isFinite(Number(body.netAmount))) {
        return NextResponse.json({ error: "Settlement reference, period and gross/fee/net amounts are required." }, { status: 400 });
      }
      rpcName = "record_mpesa_settlement";
      args = { p_organization_id: body.organizationId, p_settlement_reference: body.settlementReference.trim(), p_period_start: body.periodStart, p_period_end: body.periodEnd, p_gross_amount: Number(body.grossAmount), p_fee_amount: Number(body.feeAmount), p_net_amount: Number(body.netAmount), p_bank_reference: body.bankReference ?? null };
    } else if (body.action === "match") {
      if (!body.settlementId || !Array.isArray(body.paymentIds) || !body.paymentIds.length) return NextResponse.json({ error: "Choose a settlement and at least one payment." }, { status: 400 });
      rpcName = "match_mpesa_settlement_payments";
      args = { p_organization_id: body.organizationId, p_settlement_id: body.settlementId, p_payment_ids: body.paymentIds };
    } else {
      return NextResponse.json({ error: "Unsupported settlement action." }, { status: 400 });
    }
    const { data, error } = await supabase.rpc(rpcName, args);
    if (error) return NextResponse.json({ error: error.message }, { status: error.code === "42501" ? 403 : error.code === "23505" ? 409 : 400 });
    return NextResponse.json({ result: data }, { status: 201 });
  } catch (error) {
    console.error("Settlement action failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Settlement action could not be completed." }, { status: 503 });
  }
}
