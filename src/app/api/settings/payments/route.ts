import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { encryptCredentials } from "@/lib/payments/crypto";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
const allowed = ["mpesa", "airtel_money", "flutterwave", "paystack"] as const;
type Provider = typeof allowed[number];

async function authorizeManager() {
  const session = await createSupabaseServerClient();
  const { data: { user }, error } = await session.auth.getUser();
  if (error || !user) return { error: NextResponse.json({ error: "Sign in to manage payment providers." }, { status: 401 }) };
  const { data: memberships, error: membershipError } = await session
    .from("organization_members").select("organization_id,role").in("role", ["owner", "admin"]).limit(20);
  if (membershipError) return { error: NextResponse.json({ error: "Unable to verify organization permissions." }, { status: 403 }) };
  if (!memberships?.length) return { error: NextResponse.json({ error: "Only an organization owner or administrator can manage payment providers." }, { status: 403 }) };
  return { user, memberships };
}

export async function GET() {
  try {
    const auth = await authorizeManager();
    if ("error" in auth) return auth.error;
    const admin = createSupabaseAdminClient();
    const ids = auth.memberships.map((m) => m.organization_id);
    const { data, error } = await admin.from("payment_provider_accounts")
      .select("organization_id,provider,enabled,environment,last_four_hint,updated_at")
      .in("organization_id", ids);
    if (error) throw error;
    return NextResponse.json({ accounts: data ?? [] }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    console.error("Payment settings GET failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Payment settings are not configured on this deployment." }, { status: 503 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const auth = await authorizeManager();
    if ("error" in auth) return auth.error;
    const body = await request.json() as { organizationId?: string; provider?: string; environment?: string; credentials?: Record<string, unknown> };
    if (!body.organizationId || !auth.memberships.some((m) => m.organization_id === body.organizationId)) {
      return NextResponse.json({ error: "Choose an organization you administer." }, { status: 403 });
    }
    if (!body.provider || !allowed.includes(body.provider as Provider)) return NextResponse.json({ error: "Unsupported payment provider." }, { status: 400 });
    if (!body.credentials || typeof body.credentials !== "object" || Array.isArray(body.credentials)) return NextResponse.json({ error: "Provider credentials are required." }, { status: 400 });
    const credentials: Record<string, string> = {};
    for (const [key, value] of Object.entries(body.credentials)) {
      if (typeof value !== "string" || value.length > 1000) return NextResponse.json({ error: "Invalid credential format." }, { status: 400 });
      if (value.trim()) credentials[key] = value.trim();
    }
    if (Object.keys(credentials).length === 0) return NextResponse.json({ error: "Enter at least one credential." }, { status: 400 });
    const encrypted = encryptCredentials(credentials);
    const hints = Object.values(credentials).find((value) => value.length > 4);
    const admin = createSupabaseAdminClient();
    const { error } = await admin.from("payment_provider_accounts").upsert({
      organization_id: body.organizationId,
      provider: body.provider,
      encrypted_credentials: encrypted,
      enabled: false,
      environment: body.environment === "live" ? "live" : "test",
      configured_by: auth.user.id,
      last_four_hint: hints ? hints.slice(-4) : null,
      updated_at: new Date().toISOString(),
    }, { onConflict: "organization_id,provider" });
    if (error) throw error;
    return NextResponse.json({ saved: true, enabled: false, message: "Credentials encrypted and saved. Provider remains disabled until verification and a test transaction pass." }, { status: 201 });
  } catch (error) {
    console.error("Payment settings POST failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Could not securely save provider settings. Check server configuration." }, { status: 503 });
  }
}
