# M-PESA sandbox integration

Official reference: [Safaricom Daraja Developer Portal](https://developer.safaricom.co.ke/) and [C2B API](https://developer.safaricom.co.ke/apis/CustomerToBusiness).

## Implemented code path

- Per-organization credentials are encrypted at rest through the existing AES-256-GCM credential helper.
- STK Push uses Daraja OAuth, timestamped password, the sandbox endpoint, and a per-transaction random callback token whose hash is stored with the payment transaction.
- STK callback validates the token and checkout request ID, compares the received amount to the pending payment, queries Daraja for transaction status, and only then invokes the atomic sale-completion RPC.
- C2B validation and confirmation endpoints support Till/Paybill callback payloads. Confirmation receipts are unique per organization; duplicate callbacks do not create a second sale payment.
- C2B auto-matching only completes a draft sale when the business account reference matches its receipt number and the received amount equals the sale total. Unmatched payments remain in the reconciliation ledger rather than being guessed into a sale.

## Before sandbox testing

1. Deploy to a public HTTPS origin; callback URLs must be reachable by Safaricom.
2. In the Brilliant ERP/POS payment settings for the test organization, select M-PESA and environment test; enter the sandbox consumer key, consumer secret, shortcode, passkey, and CustomerPayBillOnline or CustomerBuyGoodsOnline.
3. Save once and copy the one-time C2B validation and confirmation URLs displayed in the success message. Treat the URLs as secrets because the query token authorizes the callback.
4. In the Daraja sandbox app, register the C2B URLs for the test shortcode. Configure the app for STK Push and use Safaricom's simulator/test phone.
5. Test a successful STK payment, customer cancellation, invalid PIN, timeout, mismatched amount, duplicate callback, and retry after a transient database error.
6. For C2B, test a known receipt-number reference, unknown reference, amount mismatch, and duplicate TransID. Confirm unmatched items stay unmatched and can be reconciled later.

## Limitations to close before production

- Sandbox credentials and a public HTTPS deployment are required to execute live sandbox calls; no sandbox transaction has been run from this environment yet.
- Daraja callback payloads do not use the same HMAC signature header pattern as Paystack. We use a random per-transaction/per-merchant callback token, request-ID and amount matching, and a Daraja status query for STK before completion. Treat callback URLs as secrets and keep request logging from recording query tokens.
- The C2B endpoints and ledger are implemented, but the app does not yet call Daraja's C2B URL-registration API automatically. Register the displayed URLs in the sandbox portal manually.
- The reconciliation UI for reviewing and manually matching unmatched Till/Paybill receipts is still to be built.
- Pending-payment stock reservations, settlement/refund handling and production merchant approval remain required before enabling live collection.
