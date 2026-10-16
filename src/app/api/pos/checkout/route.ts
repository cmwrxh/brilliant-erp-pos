import { NextRequest, NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  try {
    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      return NextResponse.json({ error: "Sign in to process a sale." }, { status: 401 });
    }

    const body = await request.json() as {
      organizationId?: string;
      locationId?: string;
      items?: { product_id: string; quantity: number; discount_amount?: number }[];
    };

    if (
      !body.organizationId ||
      !body.locationId ||
      !Array.isArray(body.items) ||
      body.items.length < 1 ||
      body.items.length > 100
    ) {
      return NextResponse.json(
        { error: "Select a branch and add at least one product." },
        { status: 400 },
      );
    }

    const items = body.items.map(item => ({
      product_id: String(item.product_id),
      quantity: Number(item.quantity),
      discount_amount: Number(item.discount_amount ?? 0),
    }));

    if (items.some(item =>
      !item.product_id ||
      !Number.isFinite(item.quantity) ||
      item.quantity <= 0 ||
      !Number.isFinite(item.discount_amount) ||
      item.discount_amount < 0
    )) {
      return NextResponse.json(
        { error: "Check the product quantities and discounts." },
        { status: 400 },
      );
    }

    const { data: membership } = await supabase
      .from("organization_members")
      .select("role")
      .eq("organization_id", body.organizationId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!membership || !["owner", "admin", "manager", "cashier"].includes(membership.role)) {
      return NextResponse.json(
        { error: "You do not have permission to process sales." },
        { status: 403 },
      );
    }

    const { data: location } = await supabase
      .from("locations")
      .select("id")
      .eq("id", body.locationId)
      .eq("organization_id", body.organizationId)
      .eq("is_active", true)
      .maybeSingle();

    if (!location) {
      return NextResponse.json(
        { error: "Choose an active branch in this workspace." },
        { status: 400 },
      );
    }

    // This RPC is the transaction boundary. Stock deduction, payment recording,
    // ledger posting and eTIMS snapshot enqueue are database-side effects of the
    // same completion transaction; never duplicate them with post-checkout writes.
    const { data: saleId, error } = await supabase.rpc("checkout_sale", {
      p_organization_id: body.organizationId,
      p_location_id: body.locationId,
      p_items: items,
      p_customer_id: null,
    });

    if (error) {
      if (error.code === "23514" && /insufficient stock|inventory valuation cannot become negative|inventory valuation balance missing/i.test(error.message)) {
        return NextResponse.json(
          { error: "Low Stock: not enough valued stock is available for one or more products. Receive stock or reduce the quantity." },
          { status: 409 },
        );
      }
      if (error.code === "23514" && /accounting period is closed|outside an open accounting period/i.test(error.message)) {
        return NextResponse.json(
          { error: "Accounting period is locked. The sale was not completed; contact an administrator." },
          { status: 409 },
        );
      }
      throw error;
    }

    const { data: sale, error: saleError } = await supabase
      .from("sales")
      .select("id,receipt_number,subtotal,discount_total,tax_total,grand_total,currency_code,created_at")
      .eq("id", saleId)
      .eq("organization_id", body.organizationId)
      .single();

    if (saleError) throw saleError;

    // The trigger-created row is the authoritative queue status. KRA submission
    // is deliberately not called here: external network effects cannot be atomic
    // with PostgreSQL, and the queue must survive/retry independently.
    const { data: outbox, error: outboxError } = await supabase
      .from("kra_etims_outbox")
      .select("status")
      .eq("organization_id", body.organizationId)
      .eq("source_sale_id", saleId)
      .maybeSingle();

    if (outboxError) throw outboxError;

    return NextResponse.json({
      sale,
      etimsStatus: outbox?.status ?? "queue_missing_check_migrations",
    }, { status: 201 });
  } catch (error) {
    console.error("POS checkout failed", error instanceof Error ? error.message : "unknown error");
    return NextResponse.json(
      { error: "Checkout failed. Confirm migrations, accounting-period status and stock availability." },
      { status: 503 },
    );
  }
}
