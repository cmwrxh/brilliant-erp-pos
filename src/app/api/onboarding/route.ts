import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export async function POST(request: NextRequest) {
  try {
    const supabase=await createSupabaseServerClient();
    const {data:{user},error:authError}=await supabase.auth.getUser();
    if(authError||!user)return NextResponse.json({error:"Sign in before creating a workspace."},{status:401});
    const body=await request.json() as {name?:string;slug?:string;businessModel?:string};
    const name=typeof body.name==="string"?body.name.trim():"";
    const slug=typeof body.slug==="string"?body.slug.trim().toLowerCase():"";
    const models=["retail","wholesale","restaurant","services","other"];
    const businessModel=typeof body.businessModel==="string"&&models.includes(body.businessModel)?body.businessModel:"retail";
    if(name.length<2||name.length>120)return NextResponse.json({error:"Business name must be 2–120 characters."},{status:400});
    if(!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)||slug.length>80)return NextResponse.json({error:"Choose a valid workspace slug."},{status:400});
    const {data:existing}=await supabase.from("organization_members").select("organization_id").limit(1);
    if(existing?.length)return NextResponse.json({error:"Your account already belongs to a workspace."},{status:409});
    const {data,error}=await supabase.rpc("create_organization_with_owner",{organization_name:name,organization_slug:slug,organization_business_model:businessModel});
    if(error){if(error.code==="23505")return NextResponse.json({error:"That workspace URL is already taken."},{status:409});throw error;}
    return NextResponse.json({organizationId:data},{status:201});
  } catch(error) {
    console.error("Workspace onboarding failed",error instanceof Error?error.message:"unknown error");
    return NextResponse.json({error:"Workspace setup is not available yet. Apply the database migrations and try again."},{status:503});
  }
}
