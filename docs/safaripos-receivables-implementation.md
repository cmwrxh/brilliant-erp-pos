# SafariPOS Receivables, Payables and Invoice Delivery Workstream

**Implementation branch:** `safaripos/receivables-settlement`  
**Review:** [PR #3](https://github.com/cmwrxh/brilliant-erp-pos/pull/3)  
**Status:** Development implementation; not production-enabled.

## Added in this workstream

- Tenant-scoped customer payment allocation records.
- `record_document_payment`: validates workspace role, outstanding balance, confirmed M-PESA reference, idempotency and chart-of-accounts setup; records the payment, updates the document balance and posts the receivables-clearing journal.
- Supplier master records, supplier bill headers and line snapshots, supplier bill payment records, and narrow RPCs for supplier creation, bill posting and bill payments.
- `record_mpesa_settlement`: records gross/fee/net settlement values and posts bank, provider-fee and M-PESA-clearing entries. The accounting invariant is gross less fees equals net.
- `match_mpesa_settlement_payments`: matches confirmed M-PESA document payments to a settlement period, rejects duplicate matches and returns an explicit variance when the matched payment total does not equal the settlement gross.
- Invoice draft and issue RPCs, immutable product/tax snapshots, receivable/revenue/output-VAT journal posting, and a durable eTIMS queue record.
- Invoice list/draft/issue API and workspace screen. The screen and APIs remain disabled unless `SAFARIPOS_INVOICE_UI_ENABLED=true`.

## Required before enabling

1. Run the disposable local Supabase migration replay and complete pgTAP suite successfully, including migrations 0017 onward.
2. Review invoice, supplier-bill, payment and settlement RPCs with test fixtures that cover two tenants, every allowed role, denied roles, retries, duplicate callbacks, overpayment and closed periods.
3. Fix product tax-code mapping and obtain CPA review of input/output VAT, supplier expense/inventory coding, settlement fee posting and invoice revenue policy.
4. Complete Daraja sandbox initiation/callback failure, timeout, replay, C2B validation/confirmation, unmatched receipts and refund tests. The settlement schema/RPC is not itself a Daraja integration or proof that funds settled.
5. Confirm the current KRA OSCU/VSCU onboarding route and required payload/signature/device requirements; implement the provider adapter and pass sandbox invoice/credit-note submission, retry and accepted-response tests.
6. Keep the invoice feature flag disabled until the above gates are met. The current issue workflow writes an internal invoice journal and a durable eTIMS queue item; it does **not** submit to KRA. A queued item is not an accepted tax invoice.
7. Do not apply migrations to the live Supabase project or promote the branch to the Coolify production deployment until CI and migration review pass.

## Important limitations

- The current draft invoice line snapshot marks the tax code as `UNMAPPED` and tax treatment as `other`. Do not use it as an official KRA tax invoice until mapping and eTIMS acceptance are implemented.
- The new migration files are additive and must be replayed from a clean disposable database. No remote database changes are performed by this branch.
- Supplier bill workflows post into the existing immutable journal, but supplier statements/imports, supplier-credit notes, payment terms, AP ageing reports and exports still require implementation and acceptance tests.
- Settlement matching uses confirmed successful document-payment records within the supplied settlement period. It does not yet import M-PESA settlement files or call a live Daraja endpoint.
- M-PESA settlement posting supports zero-fee and positive-fee statements. Provider-specific fee tax treatment and bank reconciliation tolerances require policy review.
- Formal P&L/balance sheet, official profit claims, live M-PESA collection, official eTIMS issuance and offline checkout remain gated.
