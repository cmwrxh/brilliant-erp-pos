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

export type InitializePaymentResult = { checkoutUrl?: string; providerReference?: string; message?: string };

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
  if (provider === "mpesa") {
    const { consumerKey, consumerSecret, shortcode, passkey } = credentials;
    if (!consumerKey || !consumerSecret || !shortcode || !passkey) {
      throw new Error("M-PESA consumer key, consumer secret, shortcode and Lipa Na M-PESA passkey are required.");
    }
    if (!input.phone) throw new Error("Enter the customer's Kenyan mobile number for M-PESA STK Push.");
    if (!Number.isInteger(input.amount) || input.amount < 1) {
      throw new Error("M-PESA STK Push requires a whole KES amount of at least KES 1. Adjust the sale total before requesting payment.");
    }
    // Normalize Kenyan local and international input before sending it to Daraja.
    // Removing all non-digits also safely handles spaces, + signs, brackets and hyphens.
    const digits = input.phone.replace(/\D/g, "");
    const phone = digits.startsWith("0") ? "254" + digits.slice(1) : digits;
    if (!/^254(?:7|1)\d{8}$/.test(phone)) throw new Error("Enter a valid Kenyan mobile number, e.g. 0712345678 or +254712345678.");
    const sandbox = (credentials.environment ?? "test") === "test";
    const apiBase = sandbox ? "https://sandbox.safaricom.co.ke" : "https://api.safaricom.co.ke";
    const basic = Buffer.from(consumerKey + ":" + consumerSecret).toString("base64");
    const tokenResponse = await fetch(apiBase + "/oauth/v1/generate?grant_type=client_credentials", {
      headers: { Authorization: "Basic " + basic }, cache: "no-store", signal: AbortSignal.timeout(15000),
    });
    const tokenJson = await tokenResponse.json().catch(() => ({})) as { access_token?: string; errorMessage?: string };
    if (!tokenResponse.ok || !tokenJson.access_token) throw new Error("Could not authenticate with Safaricom Daraja. Check sandbox credentials and environment.");
    const timestamp = new Intl.DateTimeFormat("en-GB", {
      timeZone: "Africa/Nairobi", year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
    }).format(new Date()).replace(/[^0-9]/g, "");
    const password = Buffer.from(shortcode + passkey + timestamp).toString("base64");
    const callback = new URL(input.callbackUrl);
    const accountType = credentials.accountType === "CustomerBuyGoodsOnline" ? "CustomerBuyGoodsOnline" : "CustomerPayBillOnline";
    const requestBody = {
      BusinessShortCode: shortcode, Password: password, Timestamp: timestamp,
      TransactionType: accountType, Amount: Math.round(input.amount), PartyA: phone,
      PartyB: shortcode, PhoneNumber: phone, CallBackURL: callback.toString(),
      AccountReference: input.reference.slice(0, 12), TransactionDesc: "Brilliant POS sale",
    };
    const response = await fetch(apiBase + "/mpesa/stkpush/v1/processrequest", {
      method: "POST", headers: { Authorization: "Bearer " + tokenJson.access_token, "Content-Type": "application/json" },
      body: JSON.stringify(requestBody), cache: "no-store", signal: AbortSignal.timeout(20000),
    });
    const result = await response.json().catch(() => ({})) as {
      ResponseCode?: string; ResponseDescription?: string; errorMessage?: string;
      CheckoutRequestID?: string; MerchantRequestID?: string; CustomerMessage?: string;
    };
    if (!response.ok || result.ResponseCode !== "0" || !result.CheckoutRequestID) {
      throw new Error(result.errorMessage ?? result.ResponseDescription ?? "Safaricom did not accept the STK Push request.");
    }
    return {
      providerReference: result.CheckoutRequestID,
      message: result.CustomerMessage ?? "M-PESA payment prompt sent. Ask the customer to enter their PIN on their phone.",
    };
  }
  throw new Error("Unsupported payment provider.");
}
