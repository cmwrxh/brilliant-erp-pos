import "server-only";

export type PaymentProvider = "flutterwave" | "paystack" | "airtel_money" | "mpesa";
export type PaymentCredentials = Record<string, string>;

export type InitializePaymentInput = {
  reference: string;
  amount: number;
  currency: string;
  email: string;
  name?: string;
  phone?: string;
  callbackUrl: string;
  metadata: Record<string, string>;
};

export type InitializePaymentResult = { checkoutUrl: string; providerReference?: string };

async function postJson(url: string, token: string, body: unknown, headers: Record<string, string> = {}) {
  const response = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
    cache: "no-store",
    signal: AbortSignal.timeout(15000),
  });
  const json = await response.json().catch(() => ({})) as { message?: unknown; status?: unknown; data?: { link?: unknown; authorization_url?: unknown; reference?: unknown } };
  if (!response.ok) throw new Error(typeof json.message === "string" ? json.message : "Payment provider request failed.");
  return json;
}

export async function initializeProviderPayment(provider: PaymentProvider, credentials: PaymentCredentials, input: InitializePaymentInput): Promise<InitializePaymentResult> {
  if (provider === "flutterwave") {
    if (!credentials.secretKey) throw new Error("Flutterwave secret key is not configured.");
    const result = await postJson("https://api.flutterwave.com/v3/payments", credentials.secretKey, {
      tx_ref: input.reference, amount: input.amount, currency: input.currency,
      redirect_url: input.callbackUrl,
      customer: { email: input.email, name: input.name, phonenumber: input.phone },
      meta: input.metadata,
      customizations: { title: "Brilliant ERP/POS", description: "Business transaction" },
    });
    const link = result.data?.link;
    if (typeof link !== "string" || !link.startsWith("https://")) throw new Error("Flutterwave did not return a valid checkout URL.");
    return { checkoutUrl: link, providerReference: input.reference };
  }
  if (provider === "paystack") {
    if (!credentials.secretKey) throw new Error("Paystack secret key is not configured.");
    const result = await postJson("https://api.paystack.co/transaction/initialize", credentials.secretKey, {
      email: input.email, amount: Math.round(input.amount * 100), currency: input.currency,
      reference: input.reference, callback_url: input.callbackUrl, metadata: input.metadata,
    });
    const link = result.data?.authorization_url;
    if (result.status !== true || typeof link !== "string" || !link.startsWith("https://")) throw new Error("Paystack did not return a valid checkout URL.");
    return { checkoutUrl: link, providerReference: typeof result.data?.reference === "string" ? result.data.reference : undefined };
  }
  if (provider === "airtel_money") {
    if (!credentials.clientId || !credentials.clientSecret || !credentials.country || !credentials.currency) {
      throw new Error("Airtel Money client ID, client secret, country and currency are required.");
    }
    if (!input.phone) throw new Error("A customer phone number is required for Airtel Money.");
    // Airtel Money is a push collection flow, not a hosted checkout. We deliberately
    // require a configured merchant API integration before initiating a real charge.
    throw new Error("Airtel Money credentials are saved, but collection initiation is not enabled until the merchant account's country-specific API contract is verified.");
  }
  throw new Error("M-Pesa collection is not configured yet.");
}
