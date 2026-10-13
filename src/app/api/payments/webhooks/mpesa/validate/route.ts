import { NextRequest } from "next/server";
import { handleC2BValidation } from "@/lib/payments/mpesa-c2b";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function POST(request:NextRequest){return handleC2BValidation(request);}
