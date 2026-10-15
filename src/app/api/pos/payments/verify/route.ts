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
  const body=await request.json() as {provider?:string;reference?:string;transactionId?:string};
  if(!body.reference||!body.provider||!["flutterwave","paystack","mpesa"].includes(body.provider))return NextResponse.json({error:"Invalid payment reference."},{status:400});
  if(body.provider==="flutterwave"&&body.transactionId!==undefined&&(typeof body.transactionId!=="string"||!/^\d{1,30}$/.test(body.transactionId)))return NextResponse.json({error:"Invalid provider transaction ID."},{status:400});
  const admin=createSupabaseAdminClient();
  const {data:tx,error:txError}=await admin.from("provider_transactions").select("id,organization_id").eq("provider",body.provider).eq("reference",body.reference).maybeSingle();
  if(txError)throw txError;
  if(!tx)return NextResponse.json({error:"Payment reference was not found."},{status:404});
  const {data:membership,error:membershipError}=await supabase.from("organization_members").select("organization_id").eq("organization_id",tx.organization_id).eq("user_id",user.id).maybeSingle();
  if(membershipError)throw membershipError;
  if(!membership)return NextResponse.json({error:"Workspace access denied."},{status:403});
  if(body.provider==="mpesa"){
   const {data:transaction,error}=await admin.from("provider_transactions").select("status,sale_id,organization_id,amount,provider_reference").eq("provider","mpesa").eq("reference",body.reference).maybeSingle();
   if(error)throw error;
   if(!transaction)return NextResponse.json({error:"Payment reference was not found."},{status:404});
   if(!transaction.sale_id)return NextResponse.json({error:"This payment is not linked to a sale."},{status:409});
   const {data:sale,error:saleError}=await admin.from("sales").select("id,receipt_number,grand_total,currency_code,status").eq("id",transaction.sale_id).eq("organization_id",transaction.organization_id).single();
   if(saleError)throw saleError;
   return NextResponse.json({ok:transaction.status==="succeeded",status:transaction.status,sale},{status:200});
  }
  const result=await verifyAndCompletePayment(body.provider as "flutterwave"|"paystack",body.reference);
  return NextResponse.json(result,{status:result.ok?200:202});
 }catch(error){console.error("Payment verification failed",error instanceof Error?error.message:"unknown error");return NextResponse.json({error:"Could not verify payment yet. Check again shortly."},{status:503});}
}
