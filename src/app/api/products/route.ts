import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const productSelect = "id,sku,barcode,name,unit,cost_price,selling_price,tax_rate,is_active,created_at";

const parseAmount = (value: unknown) =>
  typeof value === "number" && Number.isFinite(value)
    ? value
    : typeof value === "string" && value.trim() !== ""
      ? Number(value)
      : NaN;

async function getAuthorizedMembership(supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>, organizationId: string) {
  const { data: membership } = await supabase
    .from("organization_members")
    .select("role")
    .eq("organization_id", organizationId)
    .maybeSingle();

  if (!membership || !["owner", "admin", "manager", "inventory"].includes(membership.role)) {
    return false;
  }
  return true;
}

export async function GET(request: NextRequest) {
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in required." }, { status: 401 });

    const organizationId = request.nextUrl.searchParams.get("organizationId");
    if (!organizationId) return NextResponse.json({ error: "Organization is required." }, { status: 400 });

    const { data: membership } = await supabase
      .from("organization_members")
      .select("organization_id")
      .eq("organization_id", organizationId)
      .maybeSingle();
    if (!membership) return NextResponse.json({ error: "Workspace access denied." }, { status: 403 });

    const { data, error } = await supabase
      .from("products")
      .select(productSelect)
      .eq("organization_id", organizationId)
      .order("name")
      .limit(500);
    if (error) throw error;

    return NextResponse.json({ products: data ?? [] }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    console.error("Product list failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Could not load products. Check database migrations and permissions." }, { status: 503 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in required." }, { status: 401 });

    const body = await request.json() as Record<string, unknown>;
    const organizationId = typeof body.organizationId === "string" ? body.organizationId : "";
    const sku = typeof body.sku === "string" ? body.sku.trim() : "";
    const name = typeof body.name === "string" ? body.name.trim() : "";
    const barcode = typeof body.barcode === "string" ? body.barcode.trim() || null : null;
    const unit = typeof body.unit === "string" ? body.unit.trim() : "each";
    const costPrice = parseAmount(body.costPrice);
    const sellingPrice = parseAmount(body.sellingPrice);
    const taxRate = parseAmount(body.taxRate ?? 0);

    if (!organizationId || sku.length < 1 || sku.length > 80 || name.length < 2 || name.length > 160 || unit.length < 1 || unit.length > 30) {
      return NextResponse.json({ error: "Enter a valid SKU, product name and unit." }, { status: 400 });
    }
    if (!Number.isFinite(costPrice) || !Number.isFinite(sellingPrice) || !Number.isFinite(taxRate) || costPrice < 0 || sellingPrice < 0 || taxRate < 0 || taxRate > 100) {
      return NextResponse.json({ error: "Prices must be non-negative and tax must be between 0 and 100." }, { status: 400 });
    }
    if (!(await getAuthorizedMembership(supabase, organizationId))) {
      return NextResponse.json({ error: "You do not have permission to add products." }, { status: 403 });
    }

    const { data, error } = await supabase
      .from("products")
      .insert({
        organization_id: organizationId,
        sku,
        name,
        barcode,
        unit,
        cost_price: costPrice,
        selling_price: sellingPrice,
        tax_rate: taxRate,
      })
      .select(productSelect)
      .single();

    if (error) {
      if (error.code === "23505") return NextResponse.json({ error: "That SKU or barcode already exists in this workspace." }, { status: 409 });
      throw error;
    }
    return NextResponse.json({ product: data }, { status: 201 });
  } catch (error) {
    console.error("Product create failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Could not create product. Check database migrations and permissions." }, { status: 503 });
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Sign in required." }, { status: 401 });

    const body = await request.json() as Record<string, unknown>;
    const id = typeof body.id === "string" ? body.id : "";
    const organizationId = typeof body.organizationId === "string" ? body.organizationId : "";
    const sku = typeof body.sku === "string" ? body.sku.trim() : "";
    const name = typeof body.name === "string" ? body.name.trim() : "";
    const barcode = typeof body.barcode === "string" ? body.barcode.trim() || null : null;
    const unit = typeof body.unit === "string" ? body.unit.trim() : "";
    const costPrice = parseAmount(body.costPrice);
    const sellingPrice = parseAmount(body.sellingPrice);
    const taxRate = parseAmount(body.taxRate);
    const isActive = body.isActive;

    if (!id || !organizationId) return NextResponse.json({ error: "Product and workspace are required." }, { status: 400 });
    if (sku.length < 1 || sku.length > 80 || name.length < 2 || name.length > 160 || unit.length < 1 || unit.length > 30) {
      return NextResponse.json({ error: "Enter a valid SKU, product name and unit." }, { status: 400 });
    }
    if (!Number.isFinite(costPrice) || !Number.isFinite(sellingPrice) || !Number.isFinite(taxRate) || costPrice < 0 || sellingPrice < 0 || taxRate < 0 || taxRate > 100) {
      return NextResponse.json({ error: "Prices must be non-negative and tax must be between 0 and 100." }, { status: 400 });
    }
    if (typeof isActive !== "boolean") return NextResponse.json({ error: "Choose a valid product status." }, { status: 400 });
    if (!(await getAuthorizedMembership(supabase, organizationId))) {
      return NextResponse.json({ error: "You do not have permission to edit products." }, { status: 403 });
    }

    const { data, error } = await supabase
      .from("products")
      .update({
        sku,
        name,
        barcode,
        unit,
        cost_price: costPrice,
        selling_price: sellingPrice,
        tax_rate: taxRate,
        is_active: isActive,
      })
      .eq("id", id)
      .eq("organization_id", organizationId)
      .select(productSelect)
      .maybeSingle();

    if (error) {
      if (error.code === "23505") return NextResponse.json({ error: "That SKU or barcode already exists in this workspace." }, { status: 409 });
      throw error;
    }
    if (!data) return NextResponse.json({ error: "Product not found or you do not have access to edit it." }, { status: 404 });

    return NextResponse.json({ product: data }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    console.error("Product update failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json({ error: "Could not update product. Check database permissions and try again." }, { status: 503 });
  }
}
