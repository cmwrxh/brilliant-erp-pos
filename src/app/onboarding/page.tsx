import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { OnboardingForm } from "./OnboardingForm";
export default async function OnboardingPage(){try{const supabase=await createSupabaseServerClient();const {data:{user}}=await supabase.auth.getUser();if(!user)redirect("/login");const {data}=await supabase.from("organization_members").select("organization_id").limit(1);if(data?.length)redirect("/");}catch(error){if(error instanceof Error&&error.message==="NEXT_REDIRECT")throw error;}return <OnboardingForm/>;}
