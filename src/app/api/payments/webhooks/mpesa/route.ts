import { createHash,timingSafeEqual } from "node:crypto";
import { NextRequest,NextResponse } from "next/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
export const runtime="nodejs";
export const dynamic="force-dynamic";

type CallbackItem={Name?:string;Value?:string|number};
type StkCallback={MerchantRequestID?:string;CheckoutRequestID?:string;ResultCode?:number;ResultDesc?:string;CallbackMetadata?:{Item?:CallbackItem[]}};
type CallbackBody={Body?:{stkCallback?:StkCallback}};

function valueOf(items:CallbackItem[],name:string){return items.find(item=>item.Name===name)?.Value;}
function safeEqualHex(a:string,b:string){try{const left=Buffer.from(a,"hex");const right=Buffer.from(b,"hex");return left.length===right.length&&left.length>0&&timingSafeEqual(left,right);}catch{return false;}}

export async function POST(request:NextRequest){
 try{
  const reference=request.nextUrl.searchParams.get("reference")??"";
  const token=request.nextUrl.searchParams.get("token")??"";
  if(!/^ERP-[0-9a-f-]{36}$/i.test(reference)||token.length<32)return NextResponse.json({ResultCode:1,ResultDesc:"Invalid callback reference."},{status:401});
  const admin=createSupabaseAdminClient();
  const {data:transaction,error}=await admin.from("provider_transactions")
   .select("id,organization_id,sale_id,reference,provider_reference,amount,currency_code,status,callback_token_hash")
   .eq("provider","mpesa").eq("reference",reference).maybeSingle();
  if(error)throw error;
  if(!transaction||!transaction.callback_token_hash)return NextResponse.json({ResultCode:1,ResultDesc:"Unknown callback."},{status:401});
  const suppliedHash=createHash("sha256").update(token).digest("hex");
  if(!safeEqualHex(transaction.callback_token_hash,suppliedHash))return NextResponse.json({ResultCode:1,ResultDesc:"Invalid callback token."},{status:401});
  const payload=await request.json() as CallbackBody;
  const callback=payload.Body?.stkCallback;
  if(!callback?.CheckoutRequestID||!transaction.provider_reference||callback.CheckoutRequestID!==transaction.provider_reference){
   return NextResponse.json({ResultCode:1,ResultDesc:"Checkout request mismatch."},{status:400});
  }
  if(transaction.status==="succeeded"||transaction.status==="failed"||transaction.status==="cancelled"){
   return NextResponse.json({ResultCode:0,ResultDesc:"Callback already processed."});
  }
  if(Number(callback.ResultCode)!==0){
   await admin.from("provider_transactions").update({status:"failed",provider_payload:payload,callback_received_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq("id",transaction.id).eq("status","pending");
   return NextResponse.json({ResultCode:0,ResultDesc:"Payment failure recorded."});
  }
  const items=callback.CallbackMetadata?.Item??[];
  const amount=Number(valueOf(items,"Amount"));
  const receipt=String(valueOf(items,"MpesaReceiptNumber")??"");
  const phone=String(valueOf(items,"PhoneNumber")??"");
  if(!Number.isFinite(amount)||amount!==Number(transaction.amount)||!receipt||!/^\\d{10,15}$/.test(phone)){
   await admin.from("provider_transactions").update({status:"failed",provider_payload:payload,callback_received_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq("id",transaction.id).eq("status","pending");
   return NextResponse.json({ResultCode:0,ResultDesc:"Callback amount or metadata did not match the initiated payment."});
  }
  const {data:completed,error:completionError}=await admin.rpc("complete_sale",{
   p_organization_id:transaction.organization_id,p_sale_id:transaction.sale_id,
   p_method:"mpesa",p_amount:amount,p_provider_reference:receipt
  });
  if(completionError)throw completionError;
  const {error:ledgerError}=await admin.from("mpesa_transactions").upsert({
   organization_id:transaction.organization_id,provider_receipt:receipt,transaction_type:"stk_push",
   shortcode:null,account_reference:reference,phone_number:phone,amount,currency_code:"KES",
   checkout_request_id:callback.CheckoutRequestID,merchant_request_id:callback.MerchantRequestID??null,
   result_code:String(callback.ResultCode),result_description:callback.ResultDesc??null,
   matched_sale_id:transaction.sale_id,matching_status:"matched",matched_at:new Date().toISOString(),raw_payload:payload
  },{onConflict:"organization_id,provider_receipt",ignoreDuplicates:true});
  if(ledgerError)throw ledgerError;
  const {error:updateError}=await admin.from("provider_transactions").update({
   status:"succeeded",provider_payload:payload,callback_received_at:new Date().toISOString(),updated_at:new Date().toISOString()
  }).eq("id",transaction.id).eq("status","pending");
  if(updateError)throw updateError;
  return NextResponse.json({ResultCode:0,ResultDesc:"Payment processed."});
 }catch(error){
  console.error("M-PESA callback processing failed",error instanceof Error?error.message:"unknown error");
  return NextResponse.json({ResultCode:1,ResultDesc:"Callback processing failed."},{status:500});
 }
}
