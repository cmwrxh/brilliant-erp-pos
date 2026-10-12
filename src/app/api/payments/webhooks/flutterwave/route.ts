import { createHmac,timingSafeEqual } from "node:crypto";
import { NextRequest,NextResponse } from "next/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { decryptCredentials } from "@/lib/payments/crypto";
import { verifyAndCompletePayment } from "@/lib/payments/reconcile";
export const runtime="nodejs";
export async function POST(request:NextRequest){
 try{
  const raw=await request.text();
  const signature=request.headers.get("flutterwave-signature")??"";
  const legacyHash=request.headers.get("verif-hash")??"";
  const event=JSON.parse(raw) as {event?:string;type?:string;data?:{tx_ref?:string;id?:string|number;status?:string}};
  const reference=event.data?.tx_ref;
  if(!reference)return NextResponse.json({received:true});
  const admin=createSupabaseAdminClient();
  const {data:tx}=await admin.from("provider_transactions").select("organization_id").eq("provider","flutterwave").eq("reference",reference).maybeSingle();
  if(!tx)return NextResponse.json({received:true});
  const {data:account}=await admin.from("payment_provider_accounts").select("encrypted_credentials").eq("organization_id",tx.organization_id).eq("provider","flutterwave").maybeSingle();
  if(!account)return NextResponse.json({error:"Provider is not configured."},{status:401});
  const credentials=decryptCredentials(account.encrypted_credentials);
  if(!credentials.secretHash)return NextResponse.json({error:"Webhook is not configured."},{status:401});
  let valid=false;
  if(signature){const expected=createHmac("sha256",credentials.secretHash).update(raw).digest("base64");const a=Buffer.from(expected);const b=Buffer.from(signature);valid=a.length===b.length&&timingSafeEqual(a,b);}
  else if(legacyHash){const a=Buffer.from(credentials.secretHash);const b=Buffer.from(legacyHash);valid=a.length===b.length&&timingSafeEqual(a,b);}
  if(!valid)return NextResponse.json({error:"Invalid webhook signature."},{status:401});
  if((event.event==="charge.completed"||event.type==="charge.completed")&&["successful","success"].includes(event.data?.status??"")){
   if(event.data?.id!==undefined)await admin.from("provider_transactions").update({provider_reference:String(event.data.id)}).eq("provider","flutterwave").eq("reference",reference);
   await verifyAndCompletePayment("flutterwave",reference);
  }
  return NextResponse.json({received:true});
 }catch(error){console.error("Flutterwave webhook processing failed",error instanceof Error?error.message:"unknown error");return NextResponse.json({error:"Webhook processing failed."},{status:500});}
}
