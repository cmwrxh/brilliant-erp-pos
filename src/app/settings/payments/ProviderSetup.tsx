"use client";

import { useEffect, useState } from "react";
import { ArrowUpRight, CheckCircle2, LoaderCircle, LockKeyhole } from "lucide-react";

type Provider = { id: string; name: string; category: string; description: string; fields: { key: string; label: string; secret?: boolean }[]; icon: React.ComponentType<{ size?: number }> ; accent: string };
type Account = { organization_id: string; provider: string; enabled: boolean; environment: string; last_four_hint: string | null };
const required: Record<string, {key:string;label:string;secret?:boolean}[]> = {
  mpesa: [{key:"consumerKey",label:"Consumer key",secret:true},{key:"consumerSecret",label:"Consumer secret",secret:true},{key:"shortcode",label:"Business shortcode / Till number"},{key:"passkey",label:"Lipa Na M-Pesa passkey",secret:true},{key:"accountType",label:"CustomerPayBillOnline or CustomerBuyGoodsOnline"}],
  airtel_money: [{key:"clientId",label:"Client ID",secret:true},{key:"clientSecret",label:"Client secret",secret:true},{key:"country",label:"Country code (e.g. KE)"},{key:"currency",label:"Currency (e.g. KES)"}],
  flutterwave: [{key:"secretKey",label:"Secret key",secret:true},{key:"secretHash",label:"Webhook secret hash",secret:true}],
  paystack: [{key:"secretKey",label:"Secret key",secret:true}],
};

export function ProviderSetup({ providers, organizationId }: { providers: Provider[]; organizationId: string }) {
  const [accounts,setAccounts] = useState<Account[]>([]);
  const [provider,setProvider] = useState<Provider | null>(null);
  const [values,setValues] = useState<Record<string,string>>({});
  const [environment,setEnvironment] = useState("test");
  const [busy,setBusy] = useState(false);
  const [message,setMessage] = useState("");
  useEffect(()=>{ fetch("/api/settings/payments",{cache:"no-store"}).then(async r=>r.ok?r.json():{accounts:[]}).then(d=>setAccounts(d.accounts??[])).catch(()=>setAccounts([])); },[]);
  async function save(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault(); if(!provider) return; setBusy(true); setMessage("");
    try {
      const response=await fetch("/api/settings/payments",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({organizationId,provider:provider.id,environment,credentials:values})});
      const result=await response.json();
      if(!response.ok) throw new Error(result.error??"Could not save provider settings.");
      setMessage((result.message??"Saved securely.")+(result.validationUrl?" Register these URLs in your Safaricom Daraja C2B configuration. Validation: "+result.validationUrl+" Confirmation: "+result.callbackUrl:"")); setProvider(null); setValues({});
      const refresh=await fetch("/api/settings/payments",{cache:"no-store"}); if(refresh.ok){const data=await refresh.json();setAccounts(data.accounts??[]);}
    } catch(error) {setMessage(error instanceof Error?error.message:"Could not save provider settings.");}
    finally{setBusy(false);}
  }
  return <>
    <div className="provider-grid">{providers.map(p=>{const account=accounts.find(a=>a.provider===p.id&&a.organization_id===organizationId);return <article className="provider-card" key={p.id}><div className="provider-card-top"><span className={"provider-icon "+p.accent}><p.icon size={22}/></span><span className={"provider-state "+(account?"configured":"")}><span/>{account?(account.enabled?"Sandbox enabled":"Saved · "+account.environment):"Not connected"}</span></div><h2>{p.name}</h2><p className="provider-category">{p.category}</p><p className="provider-description">{p.description}</p><div className="provider-fields"><span>REQUIRED CONFIGURATION</span>{p.fields.map(field=><div key={field.key}><CheckCircle2 size={14}/>{field.label}</div>)}</div><button className="provider-connect" onClick={()=>{setProvider(p);setValues({});setMessage("");}} type="button">Configure provider <ArrowUpRight size={15}/></button>{account&&<p className="provider-saved"><LockKeyhole size={13}/> {account.enabled?"Encrypted sandbox credentials saved · live charges disabled":"Encrypted credentials saved · provider disabled"}</p>}</article>})}</div>
    {message&&!provider&&<p className="form-feedback" role="status">{message}</p>}
    {provider&&<div className="provider-modal-backdrop" role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget)setProvider(null);}}><section className="provider-modal" role="dialog" aria-modal="true" aria-labelledby="provider-modal-title"><button type="button" className="modal-close" onClick={()=>setProvider(null)} aria-label="Close">×</button><p className="eyebrow">SECURE MERCHANT SETUP</p><h2 id="provider-modal-title">Configure {provider.name}</h2><p className="muted">Credentials are sent over HTTPS and encrypted on the server before database storage. They are never returned to the browser after saving.</p><form onSubmit={save}><label className="payment-form-label">Environment<select value={environment} onChange={e=>setEnvironment(e.target.value)}><option value="test">Test / sandbox</option><option value="live">Live production</option></select></label>{(required[provider.id]??provider.fields).map(field=><label className="payment-form-label" key={field.key}>{field.label}<input autoComplete="off" required value={values[field.key]??""} type={field.secret?"password":"text"} onChange={e=>setValues(prev=>({...prev,[field.key]:e.target.value}))} placeholder={field.secret?"Enter provider credential":field.label}/></label>)}<div className="modal-security"><LockKeyhole size={15}/> Save stores encrypted credentials only. It does not activate live charges.</div>{message&&<p className="form-feedback" role="status">{message}</p>}<div className="modal-actions"><button className="provider-cancel" type="button" onClick={()=>setProvider(null)}>Cancel</button><button className="provider-connect primary" type="submit" disabled={busy}>{busy?<><LoaderCircle size={15} className="spin"/> Saving…</>:"Encrypt and save"}</button></div></form></section></div>}
  </>;
}
