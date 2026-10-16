import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

export async function GET(request: NextRequest) {
  if (process.env.SAFARIPOS_ACCOUNTING_WORKFLOWS_ENABLED !== "true") {
    return NextResponse.json({ error: "Accounting workflows remain gated pending acceptance." }, { status: 503 });
  }

  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in to view cash flow forecasts." }, { status: 401 });

    const organizationId = request.nextUrl.searchParams.get("organizationId");
    const requestedDays = Number(request.nextUrl.searchParams.get("historyDays") ?? "90");
    if (!organizationId) return NextResponse.json({ error: "Workspace is required." }, { status: 400 });
    if (!Number.isInteger(requestedDays) || requestedDays < 30 || requestedDays > 365) {
      return NextResponse.json({ error: "historyDays must be an integer between 30 and 365." }, { status: 400 });
    }

    const { data: membership, error: membershipError } = await supabase
      .from("organization_members")
      .select("organization_id")
      .eq("organization_id", organizationId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (membershipError) throw membershipError;
    if (!membership) return NextResponse.json({ error: "Workspace access denied." }, { status: 403 });

    const { data, error } = await supabase.rpc("get_cash_flow_forecast", {
      p_organization_id: organizationId,
      p_history_days: requestedDays,
    });
    if (error) throw error;
    return NextResponse.json({
      currency: "KES",
      historyDays: requestedDays,
      forecastDays: 30,
      methodology: "Posted cash/bank ledger flows; daily net-flow mean with a 95% normal-approximation band.",
      points: data ?? [],
    });
  } catch (error) {
    console.error("Cash flow forecast failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Cash flow forecast could not be loaded. Confirm migrations and ledger setup." }, { status: 503 });
  }
}
