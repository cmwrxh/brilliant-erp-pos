"use client";
import { LogOut } from "lucide-react";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";
export function SignOutButton(){async function signOut(){try{const supabase=createSupabaseBrowserClient();await supabase.auth.signOut();}finally{window.location.assign("/login");}}return <button type="button" className="sign-out-button" onClick={signOut} aria-label="Sign out" title="Sign out"><LogOut size={16}/></button>;}
