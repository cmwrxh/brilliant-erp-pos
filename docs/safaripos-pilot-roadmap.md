# SafariPOS Pilot Roadmap and Release Gates

**Current release posture:** Existing foundation is deployed, but this is not yet a certified live-trading pilot. Do not merge this branch into main or enable live financial statements until the release gates below pass.

## Current baseline (verified 2026-10-13)

- Development source: foundation/bootstrap. Coolify previously reported a successful deployment; the Payments page was retested and works.
- GitHub default branch: main. The open PR #1 is not merged. GitHub compare reports foundation/bootstrap and main have diverged (development branch 151 commits ahead and 2 behind at the time checked); reconcile history and review CI before any merge.
- Supabase project has migrations 0001–0015 recorded as applied; migrations 0014–0015 add the accounting ledger foundation and tighter permissions. The pgTAP accounting schema/immutability test script was run against this project after the privilege fix.
- Existing RLS, checkout, inventory movement, payment callback and offline/eTIMS schema foundations exist, but several integrations have not passed end-to-end acceptance.
- Accounting schema foundation is now present (migrations 0014–0015): tenant-scoped accounts, journal headers/lines, balance-at-posting guard, source idempotency, immutable posted journals, reversal RPC, period RPCs and audit log. Operational source adapters, full subledger reconciliations, retained-earnings close, statements, exports and complete acceptance suite remain.
- Branding changes and CPA policy draft are being prepared on the separate safaripos/accounting-plan branch. This branch is not the configured Coolify source and is not yet deployed.

## Five workstreams and release milestones

### 1. Tenant isolation and security
**Current:** Partial.
**Milestone:** Extend database tests across every tenant-owned table, RPC, export, audit record and service-role path; test two businesses with opposing access; verify role permissions and RLS under authenticated users.
**Acceptance:** Tenant A cannot read, infer, post, mutate, or export Tenant B data through UI, REST, RPC, direct SQL role or export endpoints; tenant tests run automatically in CI; no cross-tenant foreign-key path; secrets never reach browser bundles.

### 2. M-PESA
**Current:** Partial.
**Milestone:** Use public HTTPS Daraja sandbox endpoints; test STK initiation, success, failure, timeout, duplicate callback, C2B validation/confirmation, wrong amount, unmatched receipt, refund/reversal, provider fee and settlement matching.
**Acceptance:** Every provider event is idempotent; no callback alone can duplicate a sale; unmatched payments enter review; gross receipts, fees, refunds and net settlements reconcile to M-PESA clearing; auditable operator workflow exists; production remains disabled until merchant credentials and operational sign-off.

### 3. Offline-first POS
**Current:** Partial foundation only; offline checkout is not enabled.
**Milestone:** Add IndexedDB product/price cache and durable outbox, stable client operation IDs, reconnect sync API, retry/conflict UX, duplicate protection and stock policy.
**Acceptance:** In airplane mode, a cashier can only complete the approved offline workflow; queued receipts are visibly provisional until synced; reconnect/retry does not duplicate sales/payments/stock movements; conflicts and expired/stale prices are surfaced; stock policy is enforced; tenant data is isolated on shared devices. Decide whether payment types beyond cash are forbidden offline.

### 4. KRA eTIMS
**Current:** Partial schema/outbox foundation; not connected/certified.
**Milestone:** Obtain the current KRA spec and onboarding path, choose OSCU/VSCU, implement taxpayer/device initialization and tax-item mapping, durable invoice submission/retry, status display and credit notes linked to original SafariPOS invoices.
**Acceptance:** KRA sandbox test cases pass; accepted invoice/control-unit references are stored; rejects remain reviewable/retryable; retries do not duplicate ledger posting; credit note and original invoice linkage is correct; taxpayer/integrator approval and production credentials are documented before live invoicing.

### 5. Accounting ledger
**Current:** Not started in schema.
**Milestone A:** CPA approves account template, accrual recognition, VAT, weighted-average costing, opening-balance and period-close policy.
**Milestone B:** Add tenant-specific chart of accounts, journals/lines, immutable posting function, idempotent source posting, reversals, audit trail, period lock, retained earnings and subledger/control-account mappings.
**Milestone C:** Connect verified POS/inventory/payment/expense/supplier/asset events; implement AR/AP, inventory valuation, bank and M-PESA reconciliation, VAT reports and CSV/XLSX/PDF exports.
**Acceptance:** Every automated accounting test in docs/safaripos-accounting-cpa-review.md passes; no formal P&L/balance sheet before then; all reports derive from posted ledger lines; export matches the UI; CPA signs off on test results and posting rules.

## Brand and pilot scope

- Product-facing name: SafariPOS.
- Pilot scope: POS, inventory, M-PESA and eTIMS.
- Do not call the product a full ERP until the accounting ledger has passed acceptance.
- Customer-facing receipt and in-app labels use SafariPOS. Current code has no custom outbound email-sending implementation; Supabase Auth confirmation emails are configured in the Supabase dashboard and require a separate template update before brand migration is complete.
- The existing report page is a sales summary, not a ledger-based P&L. No formal balance sheet should be added until the ledger acceptance gate passes.

## Sequencing and reporting

1. Prepare brand and CPA policy docs on a feature branch; confirm every old customer-facing label and identify externally configured email templates.
2. Reconcile branch histories and CI; merge the reviewed pilot-scope/brand change into the development deployment branch only after review.
3. Finish tenant isolation regression tests and security review.
4. Finish M-PESA sandbox end-to-end and reconciliation.
5. Implement and test eTIMS in KRA sandbox once required onboarding/specification is available.
6. Implement offline-first checkout behind a feature flag; test retries, conflicts and device isolation.
7. Obtain CPA policy approval, then implement the ledger in small migrations and tested increments. Enable formal statements only after all accounting acceptance tests pass.
8. Promote the tested release from development to main, configure HTTPS/domain and production secrets, run smoke tests, and enable live features only after each external approval.

## Decisions and blockers

**Recommended default:** negative stock blocked; accrual basis; perpetual inventory; moving weighted-average per product/location; immutable posted journals; closed periods locked.

**Needs user/owner decision before pilot design is finalized:**
- Offline mode: allow cash-only sales while offline, or block all checkout when disconnected? Recommendation: cash-only provisional offline sales, no M-PESA/card offline.
- Pharmacy support: defer batch/expiry workflows to a separate phase unless pharmacies are part of the first pilot.
- Branding email: update Supabase Auth email templates manually or provide the approved email copy for a template migration procedure.
- KRA path: once KRA replies, confirm OSCU vs VSCU and the integrator/onboarding route. Keep live eTIMS issuance disabled until approved.
- CPA: name a reviewer and agree how they will sign off on account codes, tax rules and sample-month test output.

## Release gate

No production claim of accounting compliance, no formal P&L/balance sheet, no live M-PESA collection, no live eTIMS issuance and no offline checkout claims until the relevant workstream acceptance criteria are demonstrated with recorded tests and reproducible demo steps.
