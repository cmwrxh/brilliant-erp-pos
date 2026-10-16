import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { submitEtimsSale } from "@/lib/etims/client";
export const runtime="nodejs";
export async function POST(request:NextRequest){
 try{
  const supabase=await createSupabaseServerClient();
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)return NextResponse.json({error:"Sign in to process a sale."},{status:401});
  const body=await request.json() as {organizationId?:string;locationId?:string;items?:{product_id:string;quantity:number;discount_amount?:number}[]};
  if(!body.organizationId||!body.locationId||!Array.isArray(body.items)||body.items.length<1||body.items.length>100)return NextResponse.json({error:"Select a branch and add at least one product."},{status:400});
  const items=body.items.map(item=>({product_id:String(item.product_id),quantity:Number(item.quantity),discount_amount:Number(item.discount_amount??0)}));
  if(items.some(item=>!item.product_id||!Number.isFinite(item.quantity)||item.quantity<=0||!Number.isFinite(item.discount_amount)||item.discount_amount<0))return NextResponse.json({error:"Check the product quantities and discounts."},{status:400});
  const {data:membership}=await supabase.from("organization_members").select("role").eq("organization_id",body.organizationId).eq("user_id",user.id).maybeSingle();
  if(!membership||!["owner","admin","manager","cashier"].includes(membership.role))return NextResponse.json({error:"You do not have permission to process sales."},{status:403});
  const {data:location}=await supabase.from("locations").select("id").eq("id",body.locationId).eq("organization_id",body.organizationId).eq("is_active",true).maybeSingle();
  if(!location)return NextResponse.json({error:"Choose an active branch in this workspace."},{status:400});
  const {data,error}=await supabase.rpc("checkout_sale",{p_organization_id:body.organizationId,p_location_id:body.locationId,p_items:items,p_customer_id:null});
  if(error){if(error.code==="23514")return NextResponse.json({error:error.message.includes("Insufficient stock")?"Not enough stock for one or more products. Receive stock or reduce the quantity.":error.message},{status:409});throw error;}
  const {data:sale}=await supabase.from("sales").select("id,receipt_number,subtotal,discount_total,tax_total,grand_total,currency_code,created_at").eq("id",data).eq("organization_id",body.organizationId).single();
  // Fiscalization must never block the cashier. Until a certified KRA OSCU/VSCU
  // adapter is configured, persist an auditable record instead of sending an invented payload.
  if(sale){
   try{
    const {data:lines,error:linesError}=await supabase.from("sale_items").select("product_name_snapshot,sku_snapshot,quantity,unit_price,discount_amount,tax_amount,line_total").eq("organization_id",body.organizationId).eq("sale_id",sale.id);
    if(linesError)throw linesError;
    const payloadSnapshot={sale:{...sale,organization_id:body.organizationId},items:(lines??[]).map(line=>({itemCode:line.sku_snapshot,itemName:line.product_name_snapshot,quantity:Number(line.quantity),unitPrice:Number(line.unit_price),discountAmount:Number(line.discount_amount),taxAmount:Number(line.tax_amount),lineTotal:Number(line.line_total)})),capturedAt:new Date().toISOString()};
    const fiscalResult=await submitEtimsSale({organizationId:body.organizationId,saleId:sale.id,receiptNumber:sale.receipt_number,currencyCode:sale.currency_code,issuedAt:sale.created_at,subtotal:Number(sale.subtotal),discountTotal:Number(sale.discount_total),taxTotal:Number(sale.tax_total),grandTotal:Number(sale.grand_total),items:(lines??[]).map(line=>({itemCode:line.sku_snapshot,itemName:line.product_name_snapshot,quantity:Number(line.quantity),unitPrice:Number(line.unit_price),taxRate:0,taxableAmount:Math.max(0,Number(line.line_total)-Number(line.tax_amount)),taxAmount:Number(line.tax_amount)}))});
    const queueStatus=fiscalResult.status==="accepted"?"accepted":fiscalResult.status==="retry"?"retry":"blocked";
    const {data:outbox,error:outboxError}=await supabase.from("kra_etims_outbox").upsert({organization_id:body.organizationId,source_sale_id:sale.id,receipt_number:sale.receipt_number,payload_snapshot:payloadSnapshot,status:queueStatus,attempts:0,next_attempt_at:new Date(Date.now()+5*60*1000).toISOString(),last_error:fiscalResult.status==="accepted"?null:fiscalResult.reason,fiscal_receipt_number:fiscalResult.status==="accepted"?fiscalResult.fiscalReceiptNumber:null,fiscal_signature:fiscalResult.status==="accepted"?fiscalResult.signature??null:null,submitted_at:null,accepted_at:fiscalResult.status==="accepted"?new Date().toISOString():null,updated_at:new Date().toISOString()},{onConflict:"organization_id,source_sale_id"}).select("id").single();
    if(outboxError)throw outboxError;
    await supabase.from("kra_etims_audit_logs").insert({organization_id:body.organizationId,outbox_id:outbox.id,source_sale_id:sale.id,event_type:"checkout_fiscalization_enqueue",outcome:queueStatus,message:fiscalResult.status==="accepted"?"KRA adapter reported acceptance.":fiscalResult.reason,response_metadata:{source:"pos_checkout"}});
   }catch(etimsError){
    console.error("eTIMS enqueue failed; cashier checkout remains completed",etimsError instanceof Error?etimsError.message:"unknown error");
    try{await supabase.from("kra_etims_audit_logs").insert({organization_id:body.organizationId,source_sale_id:sale.id,event_type:"checkout_fiscalization_enqueue",outcome:"error",message:"Fiscalization queue write failed; reconcile this sale before tax reporting.",response_metadata:{source:"pos_checkout"}});}catch{}
   }
  }
  return NextResponse.json({sale,etimsStatus:"queued_or_blocked_until_kra_adapter_is_configured"},{status:201});
 }catch(error){console.error("POS checkout failed",error instanceof Error?error.message:"unknown error");return NextResponse.json({error:"Checkout failed. Confirm the latest database migrations are applied and stock is available."},{status:503});}
}
