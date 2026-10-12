import { ArrowUpRight, CheckCircle2, CircleDashed, CreditCard, LockKeyhole, Smartphone, WalletCards } from "lucide-react";
import Link from "next/link";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type Provider = { id: string; name: string; category: string; description: string; fields: string[]; icon: typeof CreditCard; accent: string };

const providers: Provider[] = [
  { id: "mpesa", name: "M-Pesa", category: "Mobile money · Kenya", description: "STK Push checkout with asynchronous payment confirmation and reconciliation.", fields: ["Consumer key", "Consumer secret", "Shortcode", "Passkey"], icon: Smartphone, accent: "mint" },
  { id: "airtel_money", name: "Airtel Money", category: "Mobile money", description: "Customer-initiated collection with server-side status verification.", fields: ["Client ID", "Client secret", "Country", "Currency"], icon: Smartphone, accent: "red" },
  { id: "flutterwave", name: "Flutterwave", category: "Cards · Mobile money · Bank", description: "Hosted checkout for supported currencies and payment methods.", fields: ["Secret key", "Webhook secret hash"], icon: WalletCards, accent: "orange" },
  { id: "paystack", name: "Paystack", category: "Cards · Bank · Mobile money", description: "Hosted checkout with server-side transaction verification.", fields: ["Secret key", "Webhook verification"], icon: CreditCard, accent: "blue" },
];

export default async function PaymentSettingsPage() {
  let signedIn = false;
  let organizationCount = 0;
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    signedIn = Boolean(user);
    if (user) {
      const { data } = await supabase.from("organization_members").select("organization_id").limit(20);
      organizationCount = data?.length ?? 0;
    }
  } catch {
    // Keep the page useful as a setup checklist when environment variables are not configured.
  }

  return <main className="settings-page">
    <div className="settings-breadcrumb"><Link href="/">Dashboard</Link><span>/</span><strong>Payment settings</strong></div>
    <header className="settings-hero"><div><p className="eyebrow">FINANCE & INTEGRATIONS</p><h1>Payment providers</h1><p className="muted">Connect payment methods your business accepts at checkout.</p></div><span className="secure-label"><LockKeyhole size={15}/> Credentials encrypted at rest</span></header>
    <section className="payment-notice"><div className="notice-icon"><CircleDashed size={19}/></div><div><strong>Setup checklist, not live payment processing</strong><p>Providers stay inactive until merchant credentials, encrypted storage, verified webhooks and a test transaction are complete. Never paste live secret keys into support chats or source code.</p></div></section>
    {!signedIn && <section className="payment-notice warning"><div className="notice-icon"><LockKeyhole size={19}/></div><div><strong>Authentication needs to be configured</strong><p>Payment credentials can only be connected by an authenticated organization owner or administrator. Configure Supabase Auth before enabling these settings.</p></div></section>}
    <div className="provider-grid">{providers.map(({id,name,category,description,fields,icon:Icon,accent})=><article className="provider-card" key={id}><div className="provider-card-top"><span className={"provider-icon "+accent}><Icon size={22}/></span><span className="provider-state"><span/>Not connected</span></div><h2>{name}</h2><p className="provider-category">{category}</p><p className="provider-description">{description}</p><div className="provider-fields"><span>REQUIRED CONFIGURATION</span>{fields.map((field)=><div key={field}><CheckCircle2 size={14}/>{field}</div>)}</div><button className="provider-connect" disabled title="Available after secure merchant onboarding is configured">Configure provider <ArrowUpRight size={15}/></button></article>)}</div>
    <section className="payment-footnote"><strong>Merchant funds and tenant isolation</strong><p>Each business must receive funds into its own approved merchant account or provider subaccount. Credentials must be encrypted server-side, never readable through the browser database API. Provider callbacks must be signature-verified and reconciled before a sale is marked paid.</p></section>
    <p className="settings-small">Workspace memberships detected: {organizationCount}. No payment credentials are currently displayed or requested on this page.</p>
  </main>;
}
