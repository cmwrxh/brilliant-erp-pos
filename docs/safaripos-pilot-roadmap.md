# SafariPOS Pilot Roadmap and Release Gates

**Release posture:** Development source is `foundation/bootstrap`. This is not yet a certified live-trading pilot. Verify the deployed commit before relying on new code. Reconcile the divergent `main` and development branch histories and review CI before promotion.

## Current baseline (2026-10-13)

- Supabase migrations 0001–0016 are recorded as applied. Migrations 0014–0016 add accounting foundations: tenant-scoped accounts, journals, balance guards, idempotent posting, immutable posted journals, audit/reversal/period functions, moving-average inventory valuation, valued receipts, and completed-sale revenue/VAT/COGS posting.
- Accounting remains **partial**. Supplier bills/AP, customer credit sales and allocations, refunds/credit notes, M-PESA fees and settlement reconciliation, expenses, opening balances, equity/drawings, cash-up differences, stocktake/expiry write-offs, fixed assets, retained earnings close, ledger reports, exports and the complete acceptance suite remain.
- RLS/security, M-PESA, offline-first and eTIMS are all **partial** pending full end-to-end acceptance. GitHub Actions now includes a disposable local Supabase database job that replays migrations 0001–0016 and runs the pgTAP suite; its first green run is still unverified, so this is not yet a passed CI gate.
- Supabase Auth email templates are configured externally and still need a separate SafariPOS branding update.

## 1. Tenant isolation and security — PARTIAL

Test every tenant-owned table, RPC, export, audit record and service-role path using at least two businesses with opposing access. Acceptance: no cross-tenant read, inference, posting, mutation or export; automated regression tests; secrets absent from browser bundles.

## 2. M-PESA — PARTIAL

Test Daraja sandbox STK initiation, success/failure/timeout, duplicate callbacks, C2B validation/confirmation, wrong amounts, unmatched receipts, refunds, provider fees and settlement matching. Acceptance: idempotent events; no duplicate sales; unmatched payments reviewable; gross receipts, fees, refunds and net settlements reconcile to M-PESA clearing. Keep production disabled until credentials and operational sign-off.

## 3. Offline-first POS — POLICY LOCKED; IMPLEMENTATION NOT COMPLETE

**Approved policy: cash-only provisional sales while offline.** Permit checkout only with cash when disconnected. Block M-PESA, card, bank transfer, credit sales, customer-account payments and all other non-cash tenders offline.

Required behaviour:
- Use a durable local outbox and unique client operation ID for every offline sale.
- Clearly label receipts **PROVISIONAL — NOT SYNCED**. Never imply that an offline sale is server-confirmed, ledger-posted or eTIMS-accepted.
- Preserve queued sales across refreshes/restarts. Never silently discard them; retries must be idempotent.
- Use tenant-scoped cached catalogue data and clear/isolate it on logout or tenant switch.
- On reconnect, validate on the server, which is authoritative for prices, stock, tax settings and posting eligibility.
- Enforce the default negative-stock block policy during reconciliation. Preserve conflicts for review; never silently rewrite or duplicate a sale.
- Do not label provisional receipts as official eTIMS tax invoices. eTIMS submission must wait until connected and the integration is approved.
- Keep offline checkout disabled until the workflow and acceptance tests pass.

Acceptance: cash-only works in airplane mode and survives restart; non-cash tenders are unavailable; stable IDs and retries do not duplicate sales, payments, stock movements or journals; stock conflicts are visible/auditable; tenant isolation and logout cleanup pass.

## 4. KRA eTIMS — PARTIAL

Obtain current KRA specifications and onboarding path; choose OSCU/VSCU; implement taxpayer/device setup, tax-item mapping, durable submission/retry, status display and credit notes linked to original invoices. Keep live issuance disabled until sandbox acceptance, required approvals and production credentials are documented.

## 5. Accounting — PARTIAL

Implemented foundation: accrual settings, tenant-scoped chart of accounts, moving-weighted-average valuation, valued stock receipts, completed-sale revenue/output VAT/COGS journals, balanced immutable postings, idempotency, audit, reversal/period RPCs and privilege guards.

Remaining: CPA policy approval; AP and AR subledgers; refunds/credit notes; product VAT codes and input VAT; M-PESA fee/refund/settlement posting; expenses; opening balances; equity/drawings; cash-up over/short; stocktake and expiry write-offs; fixed assets/depreciation; retained earnings close; ledger-based trial balance, GL/journal register, AR/AP ageing, VAT and payment reconciliation; CSV/XLSX/PDF exports; full automated acceptance suite.

Acceptance: balanced journals/trial balance; inventory valuation equals inventory control; customer balances equal AR; supplier balances equal AP; M-PESA receipts/fees/refunds/settlements reconcile; reversals retain audit history; closed periods reject backdated postings; tenant isolation passes; exports match reports. Do not add formal P&L or balance sheet until the full suite passes and a Kenyan CPA reviews the rules/results.

## Brand and pilot scope

- Product-facing name: SafariPOS. Pilot scope: POS, inventory, M-PESA and eTIMS.
- Do not call it a full ERP until accounting acceptance passes.
- Current sales summary is not a ledger-based P&L. Do not add formal financial statements before acceptance.
- Update Supabase Auth email templates separately.

## Unified invoices and full POS checklist — SCHEMA ADDED; NOT YET ACCEPTED

The detailed data model, invoice acceptance tests, full POS status/evidence table, card-route guidance, support/privacy requirements and release sequence are in [docs/safaripos-invoice-pos-acceptance.md](./safaripos-invoice-pos-acceptance.md). Additive schema migration `0017_unified_sales_documents.sql` and pgTAP contract tests are now committed on `foundation/bootstrap`. They have **not** been applied to any remote database; local CI must replay and validate them before considering the schema accepted. No invoice UI or payment/eTIMS workflow has been marked complete.

- One tenant-scoped sales-document model must serve sales, invoices and credit notes; reuse the existing immutable ledger and payment/eTIMS workflows rather than creating a separate invoice silo.
- The shared schema and contract-test draft are committed; defer invoice screens until local database CI passes and both M-PESA and eTIMS sandbox acceptance gates pass.
- Credit sales must create Accounts Receivable balances and payments must clear those balances with idempotent ledger postings. Issued invoices must enter the approved eTIMS submission workflow; an offline provisional receipt is not an official eTIMS invoice.
- Every invoice and POS checklist line has an acceptance test and evidence requirement. Do not advertise any capability until its tests pass.
- First pilot recommendation: hardware shop. Prioritize the hardware till preset, fast category/quick-button flow, product/barcode lookup, stock receipts/reorder alerts, online M-PESA, cash-up, and the shared document/accounting foundation. Defer pharmacy expiry/batch and bar-specific workflows. Keep offline checkout disabled until its cash-only acceptance suite passes.

## Sequence

1. Finish tenant-isolation/security tests.
2. Complete M-PESA sandbox and reconciliation.
3. Complete eTIMS sandbox/onboarding work when the required specification is available.
4. Implement cash-only provisional offline checkout behind a feature flag and pass the tests above.
5. Obtain CPA approval; implement remaining accounting subledgers/reports and acceptance tests.
6. Reconcile branches, pass CI, verify Coolify deployment, then promote to `main` and enable live features only after required approvals.

## Locked decisions and blockers

- Offline: **cash-only provisional sales; all non-cash tenders blocked.** This decision does not mean offline checkout is already implemented.
- Negative stock: block by default; show sync conflicts for review.
- Accounting: accrual basis, perpetual inventory, moving weighted-average per product/location, immutable posted journals, locked closed periods.
- Confirm whether pharmacy batch/expiry workflows are needed in the first pilot.
- Update Auth email templates separately; confirm KRA OSCU/VSCU path; obtain named Kenyan CPA review.

## Release gate

No claims of accounting compliance, no formal P&L/balance sheet, no live M-PESA collection, no live eTIMS issuance, and no offline checkout claims until the relevant acceptance criteria are demonstrated with recorded tests and reproducible demo steps.
