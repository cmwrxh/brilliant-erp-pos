-- Create the organization and its owner membership atomically for the signed-in user.
create or replace function public.create_organization_with_owner(
  organization_name text,
  organization_slug text,
  organization_business_model public.business_model default 'retail'
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  created_id uuid;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if char_length(trim(organization_name)) < 2 or char_length(trim(organization_name)) > 120 then
    raise exception 'Invalid organization name' using errcode = '22023';
  end if;
  if organization_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'Invalid organization slug' using errcode = '22023';
  end if;
  insert into public.organizations(name,slug,business_model)
  values (trim(organization_name),organization_slug,coalesce(organization_business_model,'retail'))
  returning id into created_id;
  insert into public.organization_members(organization_id,user_id,role)
  values (created_id,caller_id,'owner');
  return created_id;
end;
$$;
revoke all on function public.create_organization_with_owner(text,text,public.business_model) from public, anon;
grant execute on function public.create_organization_with_owner(text,text,public.business_model) to authenticated;
