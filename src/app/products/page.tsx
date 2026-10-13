import { redirect } from "next/navigation";
import Link from "next/link";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ProductManager } from "./ProductManager";
export default async function ProductsPage(){
 let user=null;let organization:{id:string;name:string}|null=null;
 try{const supabase=await createSupabaseServerClient();const result=await supabase.auth.getUser();user=result.data.user;if(user){const {data:memberships}=await supabase.from("organization_members").select("organization_id").limit(1);const id=memberships?.[0]?.organization_id;if(id){const {data}=await supabase.from("organizations").select("id,name").eq("id",id).maybeSingle();organization=data;}}}catch{}
 if(!user)redirect("/login");if(!organization)redirect("/onboarding");
 return <main className="settings-page"><div className="settings-breadcrumb"><Link href="/">Dashboard</Link><span>/</span><strong>Products</strong></div><header className="settings-hero"><div><p className="eyebrow">CATALOGUE & PRICING</p><h1>Products</h1><p className="muted">Manage SKUs, barcodes, prices and product tax settings for {organization.name}.</p></div></header><ProductManager organizationId={organization.id}/></main>;
}
