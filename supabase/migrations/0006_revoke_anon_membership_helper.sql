-- Supabase default privileges may grant exposed functions directly to anon.
revoke all on function public.is_organization_member(uuid) from public, anon;
grant execute on function public.is_organization_member(uuid) to authenticated, service_role;
