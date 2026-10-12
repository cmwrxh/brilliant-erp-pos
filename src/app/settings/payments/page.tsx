import { ArrowUpRight, CreditCard, LockKeyhole, Smartphone, WalletCards } from "lucide-react";
import Link from "next/link";
import { ProviderSetup } from "./ProviderSetup";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const providers = [
  { id: "mpesa", name: "M-Pesa", category: "Mobile money · Kenya", description: "Safaricom STK Push and server-side payment confirmation.", fields: [{key:"consumerKey",label:"Consumer key"},{key:"consumerSecret",label:"Consumer secret"},{key:"shortcode",label:"Business shortcode"},{key:"passkey",label:"Lipa Na M-Pesa passkey"}], icon: Smartphone, accent: "mint" },
  { id: "airtel_money", name: "Airtel Money", category: "Mobile money", description: "Mobile-money collection with country-specific merchant API setup.", fields: [{key:"clientId",label:"Client ID"},{key:"clientSecret",label:"Client secret"},{key:"country",label:"Country code"},{key:"currency",label:"Currency"}], icon: Smartphone, accent: "red" },
  { id: "flutterwave", name: "Flutterwave", category: "Cards · Mobile money · Bank", description: "Hosted checkout for supported currencies and payment methods.", fields: [{key:"secretKey",label:"Secret key"},{key:"secretHash",label:"Webhook secret hash"}], icon: WalletCards, accent: "orange" },
  { id: "paystack", name: "Paystack", category: "Cards · Bank · Mobile money", description: "Hosted checkout with server-side transaction verification.", fields: [{key:"secretKey",label:"Secret key"}], icon: CreditCard, accent: "blue" },
];

export default async function PaymentSettingsPage() {
  let organizations: {id:string;name:string;role:string}[] = [];
  let authReady = false;
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    authReady = Boolean(user);
    if (user) {
      const { data: memberships } = await supabase.from("organization_members").select("organization_id,role").in("role",["owner","admin"]).limit(20);
      if (memberships?.length) {
        const ids = memberships.map(m=>m.organization_id);
        const { data: orgs } = await supabase.from("organizations").select("id,name").in("id",ids);
        organizations = (orgs??[]).map(org=>({...org,role:memberships.find(m=>m.organization_id===org.id)?.role??"admin"}));
      }
    }
  } catch { /* Render the setup guidance if Supabase is not yet configured. */ }
  return <main className="settings-page">
    <div className="settings-breadcrumb"><Link href="/">Dashboard</Link><span>/</span><strong>Payment settings</strong></div>
    <header className="settings-hero"><div><p className="eyebrow">FINANCE & INTEGRATIONS</p><h1>Payment providers</h1><p className="muted">Connect the payment methods your business accepts at checkout.</p></div><span className="secure-label"><LockKeyhole size={15}/> Encrypted credentials</span></header>
    <section className="payment-notice"><div className="notice-icon"><LockKeyhole size={19}/></div><div><strong>Merchant credentials are protected</strong><p>Secrets are encrypted on the server before database storage and are never sent back to the browser. A provider remains disabled until its payment flow and webhook are verified with a test transaction.</p></div></section>
    {!authReady && <section className="payment-notice warning"><div className="notice-icon"><LockKeyhole size={19}/></div><div><strong>Supabase sign-in is not ready</strong><p>Configure Supabase Auth and environment variables before connecting a merchant account. This page does not accept credentials until the server can authenticate your organization.</p></div></section>}
    {authReady && organizations.length===0 && <section className="payment-notice warning"><div className="notice-icon"><LockKeyhole size={19}/></div><div><strong>No administrator workspace found</strong><p>Create an organization and assign your user the owner or admin role before setting up payment providers.</p></div></section>}
    {organizations.length>0 ? <><div className="organization-select-wrap"><label htmlFor="payment-organization">Business workspace</label><select id="payment-organization" defaultValue={organizations[0].id} disabled={organizations.length>1} aria-label="Business workspace">{organizations.map(org=><option value={org.id} key={org.id}>{org.name}</option>)}</select>{organizations.length>1&&<p>Selecting between multiple workspaces will be enabled in a follow-up update.</p>}</div><ProviderSetup providers={providers} organizationId={organizations[0].id}/></> : <div className="provider-grid">{providers.map(({id,name,category,description,fields,icon:Icon,accent})=><article className="provider-card" key={id}><div className="provider-card-top"><span className={"provider-icon "+accent}><Icon size={22}/></span><span className="provider-state"><span/>Setup required</span></div><h2>{name}</h2><p className="provider-category">{category}</p><p className="provider-description">{description}</p><div className="provider-fields"><span>REQUIRED CONFIGURATION</span>{fields.map(field=><div key={field.key}><ArrowUpRight size={14}/>{field.label}</div>)}</div><button className="provider-connect" disabled>Configure after sign-in <ArrowUpRight size={15}/></button></article>)}</div>}
    <section className="payment-footnote"><strong>Important before going live</strong><p>Each business must receive funds into its own approved merchant account or provider subaccount. M-Pesa and Airtel Money use asynchronous mobile-money collection flows. Payment status must be verified server-side and matched to the expected sale amount, currency and reference before a sale is marked paid.</p></section>
  </main>;
}
