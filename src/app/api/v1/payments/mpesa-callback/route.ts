import { NextRequest } from "next/server";
import { POST as handleMpesaCallback } from "@/app/api/payments/webhooks/mpesa/route";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  return handleMpesaCallback(request);
}
