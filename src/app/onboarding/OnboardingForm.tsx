"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";

export function OnboardingForm() {
  const router=useRouter();
  const [name,setName]=useState("");
  const [slug,setSlug]=useState("");
  const [model,setModel]=useState("retail");
  const [busy,setBusy]=useState(false);
  const [message,setMessage]=useState("");
  function changeName(value:string){setName(value);setSlug(value.toLowerCase().trim().replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,""));}
  async function submit(e:React.FormEvent<HTMLFormElement>){e.preventDefault();setBusy(true);setMessage("");try{const response=await fetch("/api/onboarding",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({name,slug,businessModel:model})});const data=await response.json();if(!response.ok)throw new Error(data.error??"Could not create workspace.");router.push("/");router.refresh();}catch(error){setMessage(error instanceof Error?error.message:"Could not create workspace.");}finally{setBusy(false);}}
  return <main className="auth-page"><section className="auth-card onboarding-card"><p className="eyebrow">STEP 1 · BUSINESS SETUP</p><h1>Set up your workspace</h1><p className="muted">Your workspace keeps your branches, products, staff and transactions separate from every other business.</p><form onSubmit={submit}><label className="payment-form-label">Business name<input required minLength={2} maxLength={120} value={name} onChange={e=>changeName(e.target.value)} placeholder="e.g. Market Corner"/></label><label className="payment-form-label">Workspace address / URL slug<input required pattern="[a-z0-9]+(-[a-z0-9]+)*" value={slug} onChange={e=>setSlug(e.target.value)} placeholder="market-corner"/><small>Lowercase letters, numbers and hyphens only.</small></label><label className="payment-form-label">Business type<select value={model} onChange={e=>setModel(e.target.value)}><option value="retail">Retail / Duka</option><option value="wholesale">Wholesale / Distribution</option><option value="restaurant">Restaurant / Hospitality</option><option value="services">Services</option><option value="other">Other</option></select></label><div className="modal-security">Country: Kenya · Currency: KES · Timezone: Africa/Nairobi</div><button className="auth-submit" type="submit" disabled={busy}>{busy?"Creating workspace…":"Create workspace"}</button></form>{message&&<p className="form-feedback" role="status">{message}</p>}</section></main>;
}
