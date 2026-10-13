import { redirect } from "next/navigation";
import Link from "next/link";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { AccountingManager } from "./AccountingManager";

export default async function AccountingPage() {
  let user = null;
  let organization: { id: string; name: string } | null = null;
  const enabled = process.env.SAFARIPOS_ACCOUNTING_WORKFLOWS_ENABLED === "true";
  try {
    const supabase = await createSupabaseServerClient();
    const auth = await supabase.auth.getUser();
    user = auth.data.user;
    if (user) {
      const { data: memberships } = await supabase.from("organization_members")
        .select("organization_id").eq("user_id", user.id).limit(1);
      const id = memberships?.[0]?.organization_id;
      if (id) {
        const { data } = await supabase.from("organizations").select("id,name").eq("id", id).maybeSingle();
        organization = data;
      }
    }
  } catch {}
  if (!user) redirect("/login");
  if (!organization) redirect("/onboarding");
  return <main className="settings-page">
    <div className="settings-breadcrumb"><Link href="/">Dashboard</Link><span>/</span><strong>Accounting workflows</strong></div>
    <header className="settings-hero"><div><p className="eyebrow">RECEIVABLES · PAYABLES · RECONCILIATION</p><h1>Accounting workflows</h1><p className="muted">Supplier bills, outgoing payments and M-PESA settlement reconciliation for {organization.name}.</p></div></header>
    {!enabled ? <section className="help-card" role="status"><strong>Accounting workflows are safely gated</strong><p>Enable this workspace only after migrations replay cleanly, role/security tests pass, and the accounting policies are reviewed.</p><p className="muted">Required server setting after acceptance: SAFARIPOS_ACCOUNTING_WORKFLOWS_ENABLED=true. This feature flag is off by default.</p></section> : <AccountingManager organizationId={organization.id}/>}
  </main>;
}
