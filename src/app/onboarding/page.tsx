import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { OnboardingForm } from "./OnboardingForm";

export default async function OnboardingPage() {
  let user = null;
  let hasWorkspace = false;
  try {
    const supabase = await createSupabaseServerClient();
    const result = await supabase.auth.getUser();
    user = result.data.user;
    if (user) {
      const { data } = await supabase.from("organization_members").select("organization_id").limit(1);
      hasWorkspace = Boolean(data?.length);
    }
  } catch {
    // Environment setup guidance is handled by the form and API route.
  }
  if (!user) redirect("/login");
  if (hasWorkspace) redirect("/");
  return <OnboardingForm />;
}
