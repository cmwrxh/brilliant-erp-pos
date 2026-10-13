import { redirect } from "next/navigation";
import Link from "next/link";
import { Boxes, AlertTriangle } from "lucide-react";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { StockReceivingForm } from "./StockReceivingForm";

type ProductRef={name:string;sku:string;unit:string};
type LocationRef={name:string;code:string};
type Relation<T>=T|T[]|null;
type InventoryRow={quantity:number|string;reorder_level:number|string;products:Relation<ProductRef>;locations:Relation<LocationRef>};
type Option={id:string;name:string;sku?:string;cost_price?:number|string};

export default async function InventoryPage(){
 let user=null;
 let organization:{id:string;name:string}|null=null;
 let rows:InventoryRow[]=[];
 let products:Option[]=[];
 let locations:Option[]=[];
 let error="";
 try{
  const supabase=await createSupabaseServerClient();
  const result=await supabase.auth.getUser();user=result.data.user;
  if(user){
   const {data:memberships}=await supabase.from("organization_members").select("organization_id").limit(1);
   const id=memberships?.[0]?.organization_id;
   if(id){
    const {data:org}=await supabase.from("organizations").select("id,name").eq("id",id).maybeSingle();organization=org;
    if(org){
     const [stockResult,productResult,locationResult]=await Promise.all([
      supabase.from("inventory_balances").select("quantity,reorder_level,products(name,sku,unit),locations(name,code)").eq("organization_id",id).order("updated_at",{ascending:false}).limit(500),
      supabase.from("products").select("id,name,sku").eq("organization_id",id).eq("is_active",true).order("name").limit(500),
      supabase.from("locations").select("id,name,code").eq("organization_id",id).eq("is_active",true).order("name")
     ]);
     rows=(stockResult.data??[]) as unknown as InventoryRow[];
     products=(productResult.data??[]) as Option[];
     locations=(locationResult.data??[]) as Option[];
     if(stockResult.error||productResult.error||locationResult.error)error="Some inventory data is unavailable. Check database migrations and permissions.";
    }
   }
  }
 }catch{error="Inventory data is not connected yet. Configure Supabase and apply the schema migrations.";}
 if(!user)redirect("/login");if(!organization)redirect("/onboarding");
 const low=rows.filter(row=>Number(row.quantity)<=Number(row.reorder_level));
 return <main className="settings-page"><div className="settings-breadcrumb"><Link href="/">Dashboard</Link><span>/</span><strong>Inventory</strong></div><header className="settings-hero"><div><p className="eyebrow">STOCK CONTROL</p><h1>Inventory</h1><p className="muted">Stock visibility and receiving for {organization.name}.</p></div></header><div className="inventory-summary"><article className="stat-card"><span className="stat-top">Tracked product/location pairs</span><strong className="stat-value">{rows.length}</strong></article><article className="stat-card"><span className="stat-top">Reorder alerts</span><strong className="stat-value">{low.length}</strong></article></div>{error&&<p className="form-feedback error-feedback">{error}</p>}<StockReceivingForm organizationId={organization.id} products={products} locations={locations}/><section className="catalog-table-wrap inventory-table"><div className="catalog-table-scroll"><table><thead><tr><th>PRODUCT</th><th>LOCATION</th><th>ON HAND</th><th>REORDER AT</th><th>STATUS</th></tr></thead><tbody>{rows.map((row,i)=>{const product=Array.isArray(row.products)?row.products[0]:row.products;const location=Array.isArray(row.locations)?row.locations[0]:row.locations;const isLow=Number(row.quantity)<=Number(row.reorder_level);return <tr key={i}><td><span className="catalog-product-name"><span className="catalog-product-icon"><Boxes size={16}/></span><strong>{product?.name??"Unknown product"}</strong></span><small className="catalog-subline">{product?.sku??""}</small></td><td>{location?.name??location?.code??"Unknown location"}</td><td className="amount">{Number(row.quantity).toLocaleString("en-KE")} {product?.unit??""}</td><td>{Number(row.reorder_level).toLocaleString("en-KE")}</td><td>{isLow?<span className="inventory-low"><AlertTriangle size={13}/> Reorder</span>:<span className="status completed">In stock</span>}</td></tr>})}{!rows.length&&<tr><td colSpan={5} className="empty-catalog">No stock balances yet. Receive stock above to establish the opening balance.</td></tr>}</tbody></table></div><div className="table-footer"><span>{rows.length} stock records</span><span>Stock changes are recorded in an auditable movement ledger.</span></div></section></main>;
}
