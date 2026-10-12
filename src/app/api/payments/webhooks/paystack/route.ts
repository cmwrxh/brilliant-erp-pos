import { createHmac,timingSafeEqual } from "node:crypto";
import { NextRequest,NextResponse } from "next/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { decryptCredentials } from "@/lib/payments/crypto";
import { verifyAndCompletePayment } from "@/lib/payments/reconcile";
export const runtime="nodejs";
export async function POST(request:NextRequest){
 try{
  const raw=await request.text();
  const signature=request.headers.get("x-paystack-signature")??"";
  const event=JSON.parse(raw) as {event?:string;data?:{reference?:string}};
  const reference=event.data?.reference;
  if(!reference)return NextResponse.json({received:true});
  const admin=createSupabaseAdminClient();
  const {data:tx}=await admin.from("provider_transactions").select("organization_id").eq("provider","paystack").eq("reference",reference).maybeSingle();
  if(!tx)return NextResponse.json({received:true});
  const {data:account}=await admin.from("payment_provider_accounts").select("encrypted_credentials").eq("organization_id",tx.organization_id).eq("provider","paystack").maybeSingle();
  if(!account)return NextResponse.json({error:"Provider is not configured."},{status:401});
  const credentials=decryptCredentials(account.encrypted_credentials);
  if(!credentials.secretKey)return NextResponse.json({error:"Webhook is not configured."},{status:401});
  const expected=createHmac("sha512",credentials.secretKey).update(raw).digest("hex");
  const a=Buffer.from(expected);const b=Buffer.from(signature);
  if(a.length!==b.length||!timingSafeEqual(a,b))return NextResponse.json({error:"Invalid webhook signature."},{status:401});
  if(event.event==="charge.success")await verifyAndCompletePayment("paystack",reference);
  return NextResponse.json({received:true});
 }catch(error){console.error("Paystack webhook processing failed",error instanceof Error?error.message:"unknown error");return NextResponse.json({error:"Webhook processing failed."},{status:500});}
}
