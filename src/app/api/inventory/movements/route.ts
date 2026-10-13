import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
export const runtime="nodejs";
export async function POST(request:NextRequest){
 try{
  const supabase=await createSupabaseServerClient();
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)return NextResponse.json({error:"Sign in to receive stock."},{status:401});
  const body=await request.json() as {organizationId?:string;locationId?:string;productId?:string;quantity?:number;unitCost?:number;note?:string};
  const quantity=Number(body.quantity);const unitCost=Number(body.unitCost);
  if(!body.organizationId||!body.locationId||!body.productId||!Number.isFinite(quantity)||quantity<=0||quantity>1000000||!Number.isFinite(unitCost)||unitCost<0||unitCost>1000000000)return NextResponse.json({error:"Choose a branch and product, then enter a positive quantity and a valid unit cost."},{status:400});
  const {data,error}=await supabase.rpc("record_inventory_receipt_valued",{p_organization_id:body.organizationId,p_location_id:body.locationId,p_product_id:body.productId,p_quantity:quantity,p_unit_cost:unitCost,p_note:typeof body.note==="string"?body.note.slice(0,500):null});
  if(error){if(error.code==="42501")return NextResponse.json({error:"Only an owner, administrator, manager or inventory staff member can receive stock."},{status:403});throw error;}
  return NextResponse.json({movementId:data},{status:201});
 }catch(error){console.error("Stock receiving failed",error instanceof Error?error.message:"unknown error");return NextResponse.json({error:"Stock receiving failed. Confirm migrations and workspace permissions."},{status:503});}
}
