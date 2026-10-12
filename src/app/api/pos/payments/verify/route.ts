import { NextRequest,NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { verifyAndCompletePayment } from "@/lib/payments/reconcile";
export const runtime="nodejs";
export async function POST(request:NextRequest){
 try{
  const supabase=await createSupabaseServerClient();
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)return NextResponse.json({error:"Sign in to verify this sale."},{status:401});
  const body=await request.json() as {provider?:string;reference?:string};
  if(!body.reference||!body.provider||!["flutterwave","paystack"].includes(body.provider))return NextResponse.json({error:"Invalid payment reference."},{status:400});
  const admin=createSupabaseAdminClient();
  const {data:tx}=await admin.from("provider_transactions").select("organization_id").eq("provider",body.provider).eq("reference",body.reference).maybeSingle();
  if(!tx)return NextResponse.json({error:"Payment reference was not found."},{status:404});
  const {data:membership}=await supabase.from("organization_members").select("organization_id").eq("organization_id",tx.organization_id).maybeSingle();
  if(!membership)return NextResponse.json({error:"Workspace access denied."},{status:403});
  const result=await verifyAndCompletePayment(body.provider as "flutterwave"|"paystack",body.reference);
  return NextResponse.json(result,{status:result.ok?200:202});
 }catch(error){console.error("Payment verification failed",error instanceof Error?error.message:"unknown error");return NextResponse.json({error:"Could not verify payment yet. Check again shortly."},{status:503});}
}
