# SafariPOS Unified Sales Documents and POS Acceptance Plan

**Status:** Additive migration `supabase/migrations/20261013150000_unified_sales_documents.sql` and pgTAP contract tests are committed on `foundation/bootstrap`. They have not yet passed local CI and have not been applied to any remote Supabase project. Invoice screens remain blocked until the M-PESA and eTIMS sandbox gates pass. Every acceptance item below is a release test. Do not advertise a capability as available until its test evidence is recorded.

## 1. One document model

Sales, invoices, and credit notes must use one tenant-scoped document model. Do not create a separate invoice silo or a second set of tax/payment/ledger rules.

### Proposed logical schema

The migration now declares these entities as an additive schema draft. It does not backfill or switch existing callers. Before any remote application, validate it by replaying all migrations against disposable local Supabase, review current RPCs and tenant policies, preserve existing sale IDs/posting references, and use expand/contract for the eventual caller switch.

- `sales_documents`: `id`, `organization_id`, human-readable `document_number`, `document_type` (sale, invoice, credit_note), `status` (draft, sent, partially_paid, paid, overdue, void, credited), `customer_id` nullable for walk-in sales, `source_document_id` nullable self-reference for credit notes, `issued_at`, `due_at`, `currency_code`, subtotal/discount/tax/total/paid/balance amounts in fixed-precision numeric types, `created_by`, `voided_at`, `void_reason`, and timestamps. Enforce tenant-scoped uniqueness for document numbers and tenant-scoped foreign keys.
- `sales_document_lines`: `id`, `organization_id`, `document_id`, line number, optional product/variant reference, description snapshot, quantity, unit of measure, unit price, discount, tax code/reference snapshot, taxable base, tax amount, gross line total, and optional inventory location/batch reference. Preserve issued-line snapshots so later catalogue edits cannot rewrite history.
- `sales_document_tax_lines` (or an equivalent immutable tax breakdown): tenant/document/line references, tax code and rate snapshot, taxable base, tax amount, and tax treatment. Do not assume every product has the same tax treatment.
- `document_payments`: `id`, `organization_id`, `document_id`, tender type, amount, currency, provider, provider transaction/reference, payment-link ID/URL metadata where safe, status, received/settled/refunded amounts, timestamps, and idempotency key. Never store PAN/CVV or payment secrets in this table. Provider callbacks must be signature/source-validated and idempotent.
- `document_credit_allocations`: links credit notes/refunds to the original document and, where appropriate, to the affected original lines; records reason and amounts. Do not edit or delete issued financial history to represent a credit.
- `document_ledger_postings` (or a stable source reference in the existing journal model): tenant/document/payment source references and posting purpose, unique by organization + source + purpose. Use the existing immutable journal model as the accounting source of truth; never keep a second editable ledger in the invoice subsystem.
- `document_etims_submissions`: tenant/document, provider/device/mode, KRA control/receipt identifiers, request fingerprint (not secrets), status, attempt count, next retry, submitted/accepted timestamps, error code/message, and safe response metadata. Keep a durable submission state machine and idempotency keys; do not claim an invoice is eTIMS-compliant until the authoritative accepted response and required invoice data are recorded.
- `document_delivery_events`: tenant/document, channel (email/SMS/WhatsApp/link), recipient reference, template/language, provider message ID, queued/sent/delivered/failed status, estimated and actual cost, timestamps, and idempotency key. Avoid storing unnecessary message-body PII.
- `invoice_templates`: tenant, logo asset reference, brand colours, business details snapshot/configuration, footer, template version and timestamps. Validate tenant ownership of logo assets.
- `invoice_reminder_rules`: tenant, enabled stages (before due, due date, overdue), offsets, local sending window/time zone, language, channel preferences, opt-out/suppression policy, and last-change audit.
- `recurring_invoice_schedules`: tenant/customer, template lines and tax mapping, cadence, next issue date, due-date rule, enabled/paused state, idempotent occurrence key, retry/lease state, and audit fields. Each issued occurrence becomes a normal `sales_documents` invoice with its own eTIMS submission; retries must not duplicate documents or tax submissions.
- `customer_contact_preferences` and `support_access_grants`: tenant-scoped channel consent/opt-outs and explicit, time-limited customer consent for support view-as, including actor, reason, start/expiry, revocation, and audited actions. View-as must not bypass tenant RLS or allow silent impersonation.

### Shared state and accounting rules

- Document lifecycle, payment lifecycle, eTIMS lifecycle, delivery lifecycle, and ledger-posting lifecycle are separate state machines linked to the same document ID. A single status column must not pretend to represent all of them.
- `paid` means confirmed successful payments allocated to the document cover the amount due; a payment link being opened or an STK prompt being sent is not payment.
- A credit sale posts debit Accounts Receivable and credit the appropriate revenue/output-tax accounts; inventory/COGS posting follows the accepted inventory policy. Payments debit the relevant cash/bank/M-PESA clearing account and credit Accounts Receivable. Provider fees and settlement differences post separately and reconcile to clearing.
- Credit notes link to the original invoice, reverse the correct tax/revenue/inventory/COGS treatment as applicable, and are submitted through the required eTIMS credit-note flow. No hard deletion of issued documents or posted journals; use void/reversal/credit workflows with permissions and audit.
- Every issued tax invoice must enter the eTIMS submission workflow. If eTIMS is unavailable, preserve the pending/error state and follow the confirmed KRA-approved operating procedure; never falsely label it accepted. Offline cash sales remain provisional and are not official tax invoices until online validation and eTIMS processing.
- Enforce organization scoping and least privilege with RLS, tenant-composite foreign keys, safe SECURITY DEFINER functions (fixed search_path and explicit authorization), unique idempotency constraints, and server-side validation. The browser must never hold service-role credentials.
- Use integer minor units or fixed-precision numeric amounts consistently; never floating-point money. Store timestamps in UTC and apply each business's configured time zone to due dates and reminder windows.

## 2. Invoice-system acceptance tests

Each item is **Not implemented / not verified** unless evidence is linked in the release record.

1. **Branded templates:** Create distinct per-business templates with logo, colours, registered business details and footer; preview/print/email output matches saved version; one tenant cannot read or use another tenant's assets/template.
2. **Payment links:** M-PESA STK push and supported bank/card gateway links can be initiated from an invoice. Only validated success callbacks mark a payment paid and post the matching ledger entry; failure, timeout, replay and duplicate callbacks do not create duplicate payments or journals. A payment link is never treated as a payment.
3. **Status tracking:** Verify draft, sent, partially paid, paid, overdue, void and credited transitions, including due-date boundaries, partial allocations, overpayment policy, void permissions, and credit-note linkage. UI status derives from authoritative events and balances.
4. **Client/invoice history:** A customer dashboard shows tenant-scoped invoices, credit notes, payment allocations, balances, reminders and audit history; search/filter/pagination and RLS isolation tests pass.
5. **Unlimited invoices and fair-use messaging:** No artificial invoice-count cap is imposed by the application plan; normal platform/rate/security limits remain. Email, SMS and WhatsApp send only through configured providers with tenant opt-in, queue/retry/idempotency and a documented fair-use policy. Show per-message estimated cost by channel/provider/recipient class before enabling paid messaging, and record actual provider cost where available. Verify cost estimation against provider pricing before publishing prices; no guessed price claims.
6. **Reminders:** Per-business schedules support before due, due date and overdue stages; opt-outs/suppressions work; sending is limited to sensible local business hours, supports English and Swahili, respects tenant time zones, and never sends duplicates after retry. Test cancellation after payment/credit/void and provider failure recovery.
7. **Recurring invoices:** Scheduler safely claims due occurrences with locking/leases and deterministic idempotency keys; retries/restarts produce exactly one invoice per occurrence. Each issued invoice receives its own eTIMS submission and delivery status. Test daylight-saving/time-zone edges where applicable, paused schedules, failed submissions and customer opt-out.
8. **Training/support:** Guided onboarding checklist, in-app help, searchable help centre, feedback submission and support queue are available and tenant-safe. Support view-as requires explicit, time-limited customer consent, displays a persistent indicator, records every action, can be revoked immediately, expires automatically, and never bypasses RLS or permits access to secrets/payment data. Test access denied without consent and after expiry/revocation.

## 3. Full POS acceptance checklist and evidence status

Status meanings: **Partial** = some related foundations exist, but the complete item is not accepted; **Not verified** = no recorded evidence of end-to-end acceptance; **Not started** = no implementation evidence identified. No item below is advertised as passed.

| # | Capability | Current status | Required acceptance evidence |
|---|---|---|---|
| 1 | Configurable till: categories, quick buttons, favourites per business; pharmacy, hardware and bar presets | Not verified | Save/load separate layouts for three tenants/business presets; permissions and RLS isolate settings; keyboard/touch workflow tested on low-cost Android and desktop. |
| 2 | Offline mode and automatic sync under cash-only policy | Partial (policy locked; implementation incomplete) | Airplane-mode test; cash-only accepted, every non-cash tender blocked; receipt marked PROVISIONAL — NOT SYNCED; restart persistence; 20 sales sync exactly once; conflict review; logout/business-switch cache isolation. |
| 3 | Staff accounts: cashier, manager, admin, owner; database-enforced permissions for voids, refunds, discounts, price overrides, cash-up, reports; shared-till PIN; audit log | Not verified | Role matrix and negative tests through UI and direct RPC/API; database denies unauthorized actions; PIN throttling/lockout and secure hashing; tenant-scoped append-only audit records for sensitive actions. |
| 4 | Inventory, low-stock alerts in-app/SMS/WhatsApp, reorder levels, pharmacy expiry alerts | Partial (stock foundations exist) | Threshold/reorder tests, tenant-specific alerts, deduplicated notifications and opt-outs; expiry/batch/FEFO tests for pharmacy; stock movement and valuation reconciliation. |
| 5 | M-PESA STK and card at checkout; practical card route and offline behaviour | Partial (M-PESA sandbox gate pending; card route not selected) | Daraja sandbox end-to-end; card gateway/provider sandbox and reconciliation. Online only for payment authorization/confirmation. No card, STK or bank-transfer acceptance while offline; cash-only provisional policy applies. |
| 6 | Real-time sales, stock and profit reports | Partial (sales summary is not a ledger P&L) | Sales/stock totals reconcile to source records; ledger-based profit only after accounting suite and CPA review. Until then label profit as **estimate**, disclose basis and exclude claims of audited/official profit. |
| 7 | Thermal and digital receipts; eTIMS QR | Partial (receipt/eTIMS acceptance not demonstrated) | Print test matrix for 58 mm/80 mm, supported Bluetooth/USB browser/OS combinations, clipping and totals; digital delivery channels tested; QR appears only as specified by KRA and contains the authoritative accepted receipt/invoice reference. Provisional offline receipt must not show itself as an official eTIMS invoice. |
| 8 | Training and support tooling | Not verified | Same as invoice-system acceptance test 8; onboarding/help/feedback and consent-based audited view-as pass privacy and tenant isolation tests. |

## 4. Card payments: practical decision

Evaluate a Kenya-supported, PCI-compliant gateway that offers hosted checkout/payment links and a documented API/webhook flow (for example, compare Paystack and Flutterwave eligibility, settlement currency/fees, chargebacks, refunds and merchant onboarding before choosing). Hosted payment pages or provider SDKs keep raw card data out of SafariPOS. A payment link/QR is a way to open hosted checkout, not a separate payment rail. A physical terminal requires a separately supported/acquirer-provided integration and is not assumed available from a browser POS.

Online card payments require connectivity for authorization and confirmation. Offline card acceptance is **not supported** in this plan. Do not store PAN/CVV; use provider tokens/references and verified webhooks. Selection remains pending sandbox proof and commercial review.

## 5. Delivery sequence and gates

1. **Now: data model and contract design only.** Inspect existing sale schema/RPCs, map existing IDs and posting sources, document status transitions, tax snapshots, AR/payment allocations, eTIMS state, idempotency and tenant boundaries. Add schema contract tests. Do not build invoice screens yet.
2. **Security and CI gate.** Make disposable local Supabase CI green; test RLS/tenant isolation, function privileges, idempotency, accounting invariants and staff permission matrix. Remote staging remains blocked until project/plan decision; do not pause or upgrade projects without explicit approval.
3. **M-PESA gate.** Complete STK and C2B sandbox flows, callback validation, failure/timeout/replay, unmatched queue, refunds/fees/settlements and ledger reconciliation.
4. **eTIMS gate.** Confirm current KRA specifications and OSCU/VSCU route; pass invoice/credit-note sandbox and status/retry/QR tests. Every issued invoice must submit according to the approved operating procedure.
5. **Accounting/customer balance gate.** Implement and test AR credit sales, allocations, payment/refund/credit-note postings, and reconciliation. Obtain Kenyan CPA review before formal financial statements or claims of official profit.
6. **Invoice UI only after gates 3 and 4 pass.** Then build branded invoice editor/list/detail, customer history, payment-link actions, delivery/reminder controls and recurring schedule UI. Do not expose a UI that suggests a payment or eTIMS acceptance before the backend state confirms it.
7. **Hardware-shop pilot first.** Build the smallest safe vertical slice: hardware preset till (fast category/quick buttons/favourites), product/unit and barcode search, stock receipts and reorder levels, cash + online M-PESA, customer/invoice/credit-sale model after gates, digital/thermal receipts and daily cash-up. Keep card gateway behind a provider adapter until selected/tested. Keep offline checkout disabled until its dedicated acceptance suite passes. Defer pharmacy batch/expiry and bar-specific flows from this first pilot.
8. **Support and messaging.** Add consent, audit, tenant isolation and opt-out primitives before support view-as or reminders; enable messaging only after provider costs are verified and the fair-use policy is shown to businesses.
9. **Release gate.** Each advertised feature must link to passing automated/manual test evidence, supported-device matrix and release commit. No production migrations/deploys, live payment/eTIMS enablement, or release-branch promotion without explicit approval.

## 6. Evidence register template

For every acceptance test record: test ID, code/commit, environment, steps/fixture, expected result, actual result, automated/manual, log or screenshot reference, tester, timestamp, and status. A design document, merged code, or a passing build alone is not acceptance evidence.
