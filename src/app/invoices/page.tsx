import { redirect } from "next/navigation";
import Link from "next/link";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { InvoiceManager } from "./InvoiceManager";

export default async function InvoicesPage() {
  let user = null;
  let organization: { id: string; name: string } | null = null;
  let customers: { id: string; name: string }[] = [];
  let products: { id: string; name: string; sku: string; selling_price: number; tax_rate: number }[] = [];
  let locations: { id: string; name: string }[] = [];
  const enabled = process.env.SAFARIPOS_INVOICE_UI_ENABLED === "true";
  try {
    const supabase = await createSupabaseServerClient();
    const auth = await supabase.auth.getUser();
    user = auth.data.user;
    if (user) {
      const { data: memberships } = await supabase.from("organization_members")
        .select("organization_id,role").eq("user_id", user.id).limit(1);
      const id = memberships?.[0]?.organization_id;
      if (id) {
        const { data } = await supabase.from("organizations").select("id,name").eq("id", id).maybeSingle();
        organization = data;
        if (data && enabled) {
          const [customerResult, productResult, locationResult] = await Promise.all([
            supabase.from("customers").select("id,name").eq("organization_id", id).order("name").limit(1000),
            supabase.from("products").select("id,name,sku,selling_price,tax_rate").eq("organization_id", id).eq("is_active", true).order("name").limit(2000),
            supabase.from("locations").select("id,name").eq("organization_id", id).eq("is_active", true).order("name").limit(100)
          ]);
          customers = customerResult.data ?? [];
          products = (productResult.data ?? []) as typeof products;
          locations = locationResult.data ?? [];
        }
      }
    }
  } catch {}
  if (!user) redirect("/login");
  if (!organization) redirect("/onboarding");
  return <main className="settings-page">
    <div className="settings-breadcrumb"><Link href="/">Dashboard</Link><span>/</span><strong>Invoices & receivables</strong></div>
    <header className="settings-hero"><div><p className="eyebrow">CUSTOMER BILLING</p><h1>Invoices & receivables</h1><p className="muted">Manage customer invoices and outstanding balances for {organization.name}.</p></div></header>
    {!enabled ? <section className="help-card" role="status">
      <strong>Invoice workflow is safely gated</strong>
      <p>Draft and issue actions stay disabled until M-PESA and eTIMS sandbox acceptance is recorded. This prevents a draft invoice from being mistaken for an accepted KRA tax invoice.</p>
      <p className="muted">Required server setting after acceptance: SAFARIPOS_INVOICE_UI_ENABLED=true. Do not enable it before tax-code mapping, eTIMS sandbox submission and CPA review are complete.</p>
    </section> : <InvoiceManager organizationId={organization.id} customers={customers} products={products} locations={locations} />}
  </main>;
}
