import { NextRequest } from "next/server";
import { POST as mpesaPost } from "../../../mpesa/route";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ reference: string; token: string }> },
) {
  const { reference, token } = await context.params;
  const url = new URL(request.url);
  url.searchParams.set("reference", reference);
  url.searchParams.set("token", token);

  const body = await request.text();
  const forwardedRequest = new NextRequest(url, {
    method: "POST",
    headers: request.headers,
    body,
  });

  return mpesaPost(forwardedRequest);
}
