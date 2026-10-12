import "server-only";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { decryptCredentials } from "@/lib/payments/crypto";

export async function verifyAndCompletePayment(provider:"flutterwave"|"paystack",reference:string){
 const admin=createSupabaseAdminClient();
 const {data:transaction,error:transactionError}=await admin.from("provider_transactions").select("id,organization_id,sale_id,reference,provider_reference,amount,currency_code,status").eq("provider",provider).eq("reference",reference).maybeSingle();
 if(transactionError)throw transactionError;
 if(!transaction)return {ok:false as const,status:"not_found"};
 if(transaction.status==="succeeded"){
  const {data:sale}=await admin.from("sales").select("receipt_number,grand_total,currency_code").eq("id",transaction.sale_id).single();
  return {ok:true as const,status:"succeeded",sale};
 }
 const {data:account,error:accountError}=await admin.from("payment_provider_accounts").select("encrypted_credentials").eq("organization_id",transaction.organization_id).eq("provider",provider).maybeSingle();
 if(accountError)throw accountError;
 if(!account)return {ok:false as const,status:"provider_not_configured"};
 const credentials=decryptCredentials(account.encrypted_credentials);
 let verifiedStatus="";let verifiedAmount=0;let verifiedCurrency="";let providerReference=reference;let providerId:string|number|undefined;
 if(provider==="paystack"){
  if(!credentials.secretKey)throw new Error("Paystack secret key is missing.");
  const response=await fetch("https://api.paystack.co/transaction/verify/"+encodeURIComponent(reference),{headers:{Authorization:"Bearer "+credentials.secretKey},cache:"no-store",signal:AbortSignal.timeout(15000)});
  const json=await response.json() as {status?:boolean;data?:{status?:string;amount?:number;currency?:string;reference?:string;id?:number}};
  if(!response.ok||json.status!==true||!json.data)return {ok:false as const,status:"verification_failed"};
  verifiedStatus=json.data.status??"";verifiedAmount=Number(json.data.amount)/100;verifiedCurrency=json.data.currency??"";providerReference=json.data.reference??reference;providerId=json.data.id;
 }else{
  if(!credentials.secretKey)throw new Error("Flutterwave secret key is missing.");
  const transactionId=transaction.provider_reference||reference;
  const response=await fetch("https://api.flutterwave.com/v3/transactions/"+encodeURIComponent(transactionId)+"/verify",{headers:{Authorization:"Bearer "+credentials.secretKey},cache:"no-store",signal:AbortSignal.timeout(15000)});
  const json=await response.json() as {status?:string;data?:{status?:string;amount?:number;currency?:string;tx_ref?:string;id?:string|number}};
  if(!response.ok||!json.data)return {ok:false as const,status:"verification_failed"};
  verifiedStatus=json.data.status??"";verifiedAmount=Number(json.data.amount);verifiedCurrency=json.data.currency??"";providerReference=json.data.tx_ref??reference;providerId=json.data.id;
 }
 if(verifiedStatus!=="success"&&verifiedStatus!=="successful")return {ok:false as const,status:verifiedStatus||"pending"};
 if(providerReference!==reference||!Number.isFinite(verifiedAmount)||Math.abs(verifiedAmount-Number(transaction.amount))>0.01||verifiedCurrency!==transaction.currency_code.trim()){
  await admin.from("provider_transactions").update({status:"failed",provider_payload:{reason:"verification_mismatch"},updated_at:new Date().toISOString()}).eq("id",transaction.id);
  throw new Error("Verified payment amount, currency or reference did not match the sale.");
 }
 const {error:completeError}=await admin.rpc("complete_sale",{p_organization_id:transaction.organization_id,p_sale_id:transaction.sale_id,p_method:"card",p_amount:transaction.amount,p_provider_reference:String(providerId??providerReference)});
 if(completeError)throw completeError;
 const {error:updateError}=await admin.from("provider_transactions").update({status:"succeeded",provider_reference:String(providerId??providerReference),provider_payload:{verified:true,provider},updated_at:new Date().toISOString()}).eq("id",transaction.id);
 if(updateError)throw updateError;
 const {data:sale}=await admin.from("sales").select("receipt_number,grand_total,currency_code").eq("id",transaction.sale_id).single();
 return {ok:true as const,status:"succeeded",sale};
}
