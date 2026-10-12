"use client";
import { useState } from "react";
import Link from "next/link";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

export function LoginForm() {
  const [mode,setMode] = useState<"signin"|"signup">("signin");
  const [email,setEmail] = useState("");
  const [password,setPassword] = useState("");
  const [busy,setBusy] = useState(false);
  const [message,setMessage] = useState("");
  async function submit(e:React.FormEvent<HTMLFormElement>) {
    e.preventDefault(); setBusy(true); setMessage("");
    try {
      const supabase=createSupabaseBrowserClient();
      if(mode==="signin") {
        const {error}=await supabase.auth.signInWithPassword({email,password});
        if(error) throw error;
        window.location.assign("/onboarding");
      } else {
        const {data,error}=await supabase.auth.signUp({email,password,options:{emailRedirectTo:window.location.origin+"/onboarding"}});
        if(error) throw error;
        if(data.session) window.location.assign("/onboarding");
        else setMessage("Account created. Check your email to confirm your address, then sign in.");
      }
    } catch(error) {setMessage(error instanceof Error?error.message:"Authentication failed.");}
    finally {setBusy(false);}
  }
  return <main className="auth-page"><section className="auth-card"><Link className="auth-brand" href="/"><span className="brand-mark">B</span><span><strong>brilliant</strong><small>ERP & POS</small></span></Link><p className="eyebrow">YOUR BUSINESS WORKSPACE</p><h1>{mode==="signin"?"Welcome back":"Create your account"}</h1><p className="muted">{mode==="signin"?"Sign in to manage your business operations.":"Start setting up your business on Brilliant ERP."}</p><form onSubmit={submit}><label className="payment-form-label">Email address<input type="email" autoComplete="email" required value={email} onChange={e=>setEmail(e.target.value)} placeholder="you@business.co.ke"/></label><label className="payment-form-label">Password<input type="password" autoComplete={mode==="signin"?"current-password":"new-password"} minLength={8} required value={password} onChange={e=>setPassword(e.target.value)} placeholder="At least 8 characters"/></label><button className="auth-submit" type="submit" disabled={busy}>{busy?"Please wait…":mode==="signin"?"Sign in":"Create account"}</button></form>{message&&<p className="form-feedback" role="status">{message}</p>}<p className="auth-switch">{mode==="signin"?"New to Brilliant ERP?":"Already have an account?"} <button type="button" onClick={()=>{setMode(mode==="signin"?"signup":"signin");setMessage("");}}>{mode==="signin"?"Create an account":"Sign in"}</button></p><p className="auth-legal">Your business data is protected by organization-level access controls.</p></section></main>;
}
