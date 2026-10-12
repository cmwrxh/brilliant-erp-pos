import { randomUUID } from "node:crypto";
import { NextRequest,NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { decryptCredentials } from "@/lib/payments/crypto";
import { initializeProviderPayment,type PaymentProvider } from "@/lib/payments/providers";
export const runtime="nodejs";
const supported=["flutterwave","paystack"] as const;
export async function POST(request:NextRequest){
 let organizationId="";let saleId="";
 try{
  const session=await createSupabaseServerClient();
  const {data:{user}}=await session.auth.getUser();
  if(!user)return NextResponse.json({error:"Sign in before starting checkout."},{status:401});
  const body=await request.json() as {organizationId?:string;locationId?:string;provider?:string;email?:string;name?:string;phone?:string;items?:{product_id:string;quantity:number;discount_amount?:number}[]};
  organizationId=body.organizationId??"";
  if(!organizationId||!body.locationId||!body.provider||!supported.includes(body.provider as typeof supported[number])||!Array.isArray(body.items)||!body.items.length||body.items.length>100)return NextResponse.json({error:"Invalid payment request."},{status:400});
  const email=typeof body.email==="string"?body.email.trim():"";
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return NextResponse.json({error:"Enter a valid customer email for hosted checkout."},{status:400});
  const {data:membership}=await session.from("organization_members").select("role").eq("organization_id",organizationId).maybeSingle();
  if(!membership||!["owner","admin","manager","cashier"].includes(membership.role))return NextResponse.json({error:"Workspace access denied."},{status:403});
  const admin=createSupabaseAdminClient();
  const {data:account,error:accountError}=await admin.from("payment_provider_accounts").select("encrypted_credentials,enabled,environment").eq("organization_id",organizationId).eq("provider",body.provider).maybeSingle();
  if(accountError)throw accountError;
  if(!account||!account.enabled||account.environment!=="test")return NextResponse.json({error:"Only a configured sandbox account can start checkout. Live payments are not enabled."},{status:409});
  const credentials=decryptCredentials(account.encrypted_credentials);
  const items=body.items.map(item=>({product_id:String(item.product_id),quantity:Number(item.quantity),discount_amount:Number(item.discount_amount??0)}));
  if(items.some(item=>!item.product_id||!Number.isFinite(item.quantity)||item.quantity<=0||!Number.isFinite(item.discount_amount)||item.discount_amount<0))return NextResponse.json({error:"Check the product quantities and discounts."},{status:400});
  const {data:location}=await session.from("locations").select("id").eq("id",body.locationId).eq("organization_id",organizationId).eq("is_active",true).maybeSingle();
  if(!location)return NextResponse.json({error:"Choose an active branch."},{status:400});
  const {data:newSale,error:saleError}=await session.rpc("create_sale_draft",{p_organization_id:organizationId,p_location_id:body.locationId,p_items:items,p_customer_id:null});
  if(saleError)throw saleError;
  saleId=String(newSale);
  const {data:sale,error:fetchSaleError}=await session.from("sales").select("id,grand_total,currency_code,receipt_number").eq("id",saleId).eq("organization_id",organizationId).single();
  if(fetchSaleError||!sale)throw fetchSaleError??new Error("Could not load the draft sale.");
  if(Number(sale.grand_total)<=0)throw new Error("Sale total must be greater than zero.");
  const {data:lines,error:linesError}=await session.from("sale_items").select("product_id,quantity").eq("organization_id",organizationId).eq("sale_id",saleId);
  if(linesError)throw linesError;
  for(const line of lines??[]){
    const {data:balance}=await session.from("inventory_balances").select("quantity").eq("organization_id",organizationId).eq("location_id",body.locationId).eq("product_id",line.product_id).maybeSingle();
    if(!balance||Number(balance.quantity)<Number(line.quantity)){
      await admin.from("sales").update({status:"voided"}).eq("id",saleId).eq("organization_id",organizationId);
      saleId="";
      return NextResponse.json({error:"Not enough stock for one or more products. Receive stock before charging a customer."},{status:409});
    }
  }
  const reference="ERP-"+randomUUID();
  const {error:transactionError}=await admin.from("provider_transactions").insert({organization_id:organizationId,sale_id:saleId,provider:body.provider,reference,amount:sale.grand_total,currency_code:sale.currency_code,status:"pending"});
  if(transactionError)throw transactionError;
  const base=(process.env.APP_BASE_URL??request.nextUrl.origin).replace(/\/$/,"");
  try{
    const initialized=await initializeProviderPayment(body.provider as PaymentProvider,credentials,{reference,amount:Number(sale.grand_total),currency:sale.currency_code,email,name:typeof body.name==="string"?body.name.slice(0,120):undefined,phone:typeof body.phone==="string"?body.phone.slice(0,30):undefined,callbackUrl:base+"/payments/return?provider="+body.provider,metadata:{organization_id:organizationId,sale_id:saleId}});
    return NextResponse.json({checkoutUrl:initialized.checkoutUrl,reference,receiptNumber:sale.receipt_number},{status:201});
  }catch(error){
    await admin.from("provider_transactions").update({status:"failed",updated_at:new Date().toISOString()}).eq("reference",reference);
    await admin.from("sales").update({status:"voided"}).eq("id",saleId).eq("organization_id",organizationId);
    throw error;
  }
 }catch(error){
  console.error("Hosted checkout initialization failed",error instanceof Error?error.message:"unknown error");
  return NextResponse.json({error:error instanceof Error?error.message:"Could not start hosted checkout."},{status:503});
 }
}
