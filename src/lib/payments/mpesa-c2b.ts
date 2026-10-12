import { createHash } from "node:crypto";
import { NextRequest,NextResponse } from "next/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { decryptCredentials } from "@/lib/payments/crypto";

type C2BPayload={
 TransID?:string;TransAmount?:string|number;BusinessShortCode?:string;BillRefNumber?:string;
 MSISDN?:string|number;TransTime?:string;ThirdPartyTransID?:string;
};
const accepted=()=>NextResponse.json({ResultCode:0,ResultDesc:"Accepted"});
const failed=(message:string,status=400)=>NextResponse.json({ResultCode:1,ResultDesc:message},{status});

async function findAccount(token:string){
 if(token.length<32)return null;
 const hash=createHash("sha256").update(token).digest("hex");
 const admin=createSupabaseAdminClient();
 const {data,error}=await admin.from("payment_provider_accounts")
  .select("organization_id,encrypted_credentials,environment")
  .eq("provider","mpesa").eq("c2b_callback_token_hash",hash).maybeSingle();
 if(error)throw error;
 return data;
}
function parseTransactionTime(value?:string){
 if(!value||!/^\d{14}$/.test(value))return null;
 const iso=value.slice(0,4)+"-"+value.slice(4,6)+"-"+value.slice(6,8)+"T"+value.slice(8,10)+":"+value.slice(10,12)+":"+value.slice(12,14)+"+03:00";
 const date=new Date(iso);return Number.isNaN(date.getTime())?null:date.toISOString();
}

export async function handleC2BValidation(request:NextRequest){
 try{
  const token=request.nextUrl.searchParams.get("token")??"";
  const account=await findAccount(token);
  if(!account)return failed("Unknown merchant callback.",401);
  const body=await request.json() as C2BPayload;
  const credentials=decryptCredentials(account.encrypted_credentials);
  if(!body.BusinessShortCode||String(body.BusinessShortCode)!==credentials.shortcode)return failed("Business shortcode mismatch.",401);
  const amount=Number(body.TransAmount);
  if(!Number.isFinite(amount)||amount<=0||!body.TransID)return failed("Invalid transaction details.");
  return accepted();
 }catch(error){
  console.error("M-PESA C2B validation failed",error instanceof Error?error.message:"unknown error");
  return failed("Validation could not be completed.",500);
 }
}

export async function handleC2BConfirmation(request:NextRequest){
 try{
  const token=request.nextUrl.searchParams.get("token")??"";
  const account=await findAccount(token);
  if(!account)return failed("Unknown merchant callback.",401);
  const body=await request.json() as C2BPayload;
  const credentials=decryptCredentials(account.encrypted_credentials);
  if(!body.BusinessShortCode||String(body.BusinessShortCode)!==credentials.shortcode)return failed("Business shortcode mismatch.",401);
  const amount=Number(body.TransAmount);
  const receipt=String(body.TransID??"");
  if(!receipt||!Number.isFinite(amount)||amount<=0)return failed("Invalid transaction details.");
  const admin=createSupabaseAdminClient();
  const {data:existing,error:existingError}=await admin.from("mpesa_transactions").select("id,matching_status")
   .eq("organization_id",account.organization_id).eq("provider_receipt",receipt).maybeSingle();
  if(existingError)throw existingError;
  if(existing?.matching_status==="matched"||existing?.matching_status==="ignored"||existing?.matching_status==="reversed")return accepted();
  if(!existing){
   const {error:insertError}=await admin.from("mpesa_transactions").insert({
    organization_id:account.organization_id,provider_receipt:receipt,transaction_type:"c2b",
    shortcode:String(body.BusinessShortCode),account_reference:String(body.BillRefNumber??body.ThirdPartyTransID??"").slice(0,120)||null,
    phone_number:String(body.MSISDN??"").slice(0,20)||null,amount,currency_code:"KES",
    transaction_time:parseTransactionTime(body.TransTime),matching_status:"unmatched",
    raw_payload:body
   });
   if(insertError&&insertError.code!=="23505")throw insertError;
  }
  const accountReference=String(body.BillRefNumber??body.ThirdPartyTransID??"").trim();
  if(!accountReference)return accepted();
  const {data:sales,error:salesError}=await admin.from("sales").select("id,grand_total,status,location_id")
   .eq("organization_id",account.organization_id).eq("receipt_number",accountReference).limit(2);
  if(salesError)throw salesError;
  if(!sales||sales.length!==1||Number(sales[0].grand_total)!==amount||sales[0].status!=="draft")return accepted();
  const sale=sales[0];
  const {error:completionError}=await admin.rpc("complete_sale",{
   p_organization_id:account.organization_id,p_sale_id:sale.id,p_method:"mpesa",
   p_amount:amount,p_provider_reference:receipt
  });
  if(completionError){
   console.error("M-PESA C2B auto-match deferred",completionError.message);
   return accepted();
  }
  const {error:updateError}=await admin.from("mpesa_transactions").update({
   matched_sale_id:sale.id,matching_status:"matched",matched_at:new Date().toISOString()
  }).eq("organization_id",account.organization_id).eq("provider_receipt",receipt);
  if(updateError)throw updateError;
  return accepted();
 }catch(error){
  console.error("M-PESA C2B confirmation failed",error instanceof Error?error.message:"unknown error");
  return failed("Confirmation processing failed.",500);
 }
}
