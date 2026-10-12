-- Initial tenant-aware schema for Brilliant ERP/POS.
-- Review and test in a non-production Supabase project before applying.

create extension if not exists pgcrypto;
create type public.business_role as enum ('owner','admin','manager','cashier','inventory');
create type public.business_model as enum ('retail','wholesale','restaurant','services','other');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 120),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  business_model public.business_model not null default 'retail',
  country_code char(2) not null default 'KE',
  currency_code char(3) not null default 'KES',
  timezone text not null default 'Africa/Nairobi',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.business_role not null default 'cashier',
  created_at timestamptz not null default now(),
  primary key (organization_id,user_id)
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  code text not null,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id,code),
  unique (organization_id,id)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sku text not null,
  barcode text,
  name text not null,
  description text,
  unit text not null default 'each',
  cost_price numeric(14,2) not null default 0 check (cost_price >= 0),
  selling_price numeric(14,2) not null default 0 check (selling_price >= 0),
  tax_rate numeric(6,3) not null default 0 check (tax_rate between 0 and 100),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,sku),
  unique (organization_id,barcode),
  unique (organization_id,id)
);

create table public.inventory_balances (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null,
  product_id uuid not null,
  quantity numeric(14,3) not null default 0,
  reorder_level numeric(14,3) not null default 0 check (reorder_level >= 0),
  updated_at timestamptz not null default now(),
  primary key (location_id,product_id),
  foreign key (organization_id,location_id) references public.locations(organization_id,id) on delete cascade,
  foreign key (organization_id,product_id) references public.products(organization_id,id) on delete cascade
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  notes text,
  created_at timestamptz not null default now(),
  unique (organization_id,id)
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  location_id uuid not null,
  receipt_number text not null,
  customer_id uuid,
  cashier_user_id uuid references auth.users(id) on delete set null,
  currency_code char(3) not null default 'KES',
  subtotal numeric(14,2) not null check (subtotal >= 0),
  discount_total numeric(14,2) not null default 0 check (discount_total >= 0),
  tax_total numeric(14,2) not null default 0 check (tax_total >= 0),
  grand_total numeric(14,2) not null check (grand_total >= 0),
  status text not null default 'completed' check (status in ('draft','completed','voided','refunded')),
  idempotency_key text,
  created_at timestamptz not null default now(),
  unique (organization_id,receipt_number),
  unique (organization_id,id),
  foreign key (organization_id,location_id) references public.locations(organization_id,id),
  foreign key (organization_id,customer_id) references public.customers(organization_id,id),
  unique (organization_id,idempotency_key)
);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sale_id uuid not null,
  product_id uuid not null,
  product_name_snapshot text not null,
  sku_snapshot text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(14,2) not null check (line_total >= 0),
  foreign key (organization_id,sale_id) references public.sales(organization_id,id) on delete cascade,
  foreign key (organization_id,product_id) references public.products(organization_id,id)
);

create table public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sale_id uuid not null,
  method text not null check (method in ('cash','mpesa','card','bank_transfer','credit','other')),
  amount numeric(14,2) not null check (amount > 0),
  provider_reference text,
  status text not null default 'recorded' check (status in ('pending','recorded','failed','reversed')),
  created_at timestamptz not null default now(),
  foreign key (organization_id,sale_id) references public.sales(organization_id,id) on delete cascade
);

create index organization_members_user_idx on public.organization_members(user_id);
create index products_org_name_idx on public.products(organization_id,name);
create index inventory_org_location_idx on public.inventory_balances(organization_id,location_id);
create index sales_org_created_idx on public.sales(organization_id,created_at desc);
create index sale_items_sale_idx on public.sale_items(organization_id,sale_id);
create index sale_payments_sale_idx on public.sale_payments(organization_id,sale_id);

-- Security-definer membership helper avoids recursive RLS evaluation.
create or replace function public.is_organization_member(target_organization_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.organization_members m
    where m.organization_id = target_organization_id
      and m.user_id = (select auth.uid())
  );
$$;
revoke all on function public.is_organization_member(uuid) from public;
grant execute on function public.is_organization_member(uuid) to authenticated;

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.locations enable row level security;
alter table public.products enable row level security;
alter table public.inventory_balances enable row level security;
alter table public.customers enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.sale_payments enable row level security;

create policy "Members read organizations" on public.organizations for select to authenticated using (public.is_organization_member(id));
create policy "Members read memberships" on public.organization_members for select to authenticated using (public.is_organization_member(organization_id));

create policy "Members read locations" on public.locations for select to authenticated using (public.is_organization_member(organization_id));
create policy "Managers manage locations" on public.locations for all to authenticated
using (exists (select 1 from public.organization_members m where m.organization_id=locations.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')))
with check (exists (select 1 from public.organization_members m where m.organization_id=locations.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')));

create policy "Members read products" on public.products for select to authenticated using (public.is_organization_member(organization_id));
create policy "Staff manage products" on public.products for all to authenticated
using (exists (select 1 from public.organization_members m where m.organization_id=products.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','inventory')))
with check (exists (select 1 from public.organization_members m where m.organization_id=products.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','inventory')));

create policy "Members read inventory" on public.inventory_balances for select to authenticated using (public.is_organization_member(organization_id));
create policy "Inventory staff manage balances" on public.inventory_balances for all to authenticated
using (exists (select 1 from public.organization_members m where m.organization_id=inventory_balances.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','inventory')))
with check (exists (select 1 from public.organization_members m where m.organization_id=inventory_balances.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','inventory')));

create policy "Members read customers" on public.customers for select to authenticated using (public.is_organization_member(organization_id));
create policy "Staff manage customers" on public.customers for all to authenticated
using (exists (select 1 from public.organization_members m where m.organization_id=customers.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','cashier')))
with check (exists (select 1 from public.organization_members m where m.organization_id=customers.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','cashier')));

create policy "Members read sales" on public.sales for select to authenticated using (public.is_organization_member(organization_id));
create policy "Staff create sales" on public.sales for insert to authenticated with check (cashier_user_id=(select auth.uid()) and public.is_organization_member(organization_id));
create policy "Managers update sales" on public.sales for update to authenticated
using (exists (select 1 from public.organization_members m where m.organization_id=sales.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')))
with check (exists (select 1 from public.organization_members m where m.organization_id=sales.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager')));

create policy "Members read sale items" on public.sale_items for select to authenticated using (public.is_organization_member(organization_id));
create policy "Staff add sale items" on public.sale_items for insert to authenticated with check (exists (select 1 from public.organization_members m where m.organization_id=sale_items.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','cashier')));
create policy "Members read payments" on public.sale_payments for select to authenticated using (public.is_organization_member(organization_id));
create policy "Staff add payments" on public.sale_payments for insert to authenticated with check (exists (select 1 from public.organization_members m where m.organization_id=sale_payments.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','cashier')));

-- Organization provisioning, membership changes, checkout finalization, stock ledger
-- writes, refunds, and payment callbacks must be audited server-side transactions.
-- Do not expose the Supabase service-role key to browsers.
