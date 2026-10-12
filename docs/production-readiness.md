# Production readiness and delivery plan

## Implemented in the current branch

- Next.js/TypeScript app foundation, sign-in/onboarding, organization workspaces and role-aware UI.
- Shared schema for organizations, locations, products, inventory, customers, sales, sale items and payments.
- PostgreSQL RLS enabled on all 15 tenant business tables; generated `tenant_id` aliases map to canonical organization IDs. Tenant-boundary policies are read-only, with role-specific write policies or trusted RPCs.
- Transactional inventory movements and cash checkout; Flutterwave/Paystack sandbox hosted checkout with server-side verification and signed webhook handlers.
- Encrypted payment-provider credential storage and Dockerfile-based Coolify deployment configuration.
- Durable eTIMS submission/retry, M-PESA collection/reconciliation and offline-sync idempotency schema.
- M-PESA sandbox STK initiation, token-protected STK callback with Daraja status query, C2B validation/confirmation endpoints, and receipt/reference/amount-based auto-matching. Code is not yet sandbox-tested.

## Important status distinction

A schema foundation is not an end-to-end integration. KRA eTIMS is **not connected** until the taxpayer is onboarded, the OSCU/VSCU specification is implemented against KRA's sandbox, test cases pass, and KRA certification/approval is complete. KRA says system-to-system integrators must go through development, testing, vetting and certification, and credit notes must be generated through the solution that issued the original invoice.

M-PESA STK and C2B code paths are implemented but still need public-HTTPS sandbox testing. Daraja callbacks do not provide a Paystack-style HMAC signature header; this implementation uses random per-transaction/per-merchant callback tokens, request/amount matching and a Daraja status query for STK. C2B URL registration is manual in the Daraja portal, and the unmatched-receipt reconciliation UI, settlement/refunds/reversals and production credentials remain outstanding.

Offline-first checkout is **not yet enabled in the POS UI**. Migration 0008 provides an idempotency ledger, but the browser IndexedDB outbox, offline product/price cache, conflict handling, sync API, and stock reservation policy are still required. Do not claim that offline sales can currently be completed.

## Tenant isolation

The database currently uses `organization_id` as the tenant key, not a separate `tenant_id` column. This is the canonical foreign-key key across existing tables. Do not add a second writable tenant ID that can drift from organization_id. If a literal `tenant_id` naming convention is required across every table, perform a coordinated schema/API migration with compatibility views and regression tests rather than adding a duplicate source of truth.

RLS is enabled on 15 tenant business tables. pgTAP schema assertions and a two-tenant product read/insert/update/delete regression test have been added and executed against the connected database; broader coverage is still needed for every table, sensitive RPC, service-role path and storage objects. The platform-level `calculator_leads` table is not tenant-owned and must be reviewed separately. The platform-level `calculator_leads` table is not tenant-owned and must be reviewed separately for data minimization and access policy.

## Before Coolify deployment

1. Confirm the intended Supabase project is the staging/production target; apply and verify migrations 0001–0013 (including the restored `0009_explicit_tenant_id_rls.sql` source file).
2. Run the GitHub Actions checks and database isolation tests.
3. Add production environment variables in Coolify: Supabase URL, anon/publishable key, service-role key, 32-byte payment encryption key, and exact HTTPS APP_BASE_URL. Keep secrets out of Git.
4. Configure Supabase Auth redirect URLs, domain and TLS.
5. Deploy the Dockerfile build on port 3000 and verify /api/health.
6. Run end-to-end test transactions with sandbox credentials, duplicate webhooks, provider timeouts, insufficient stock, and tenant-crossing attempts.
7. Keep live payments and tax invoice issuance disabled until provider/KRA onboarding and certification requirements are met.

## External dependencies / blockers

- KRA taxpayer's eTIMS onboarding and OSCU/VSCU sandbox credentials/specification and certification.
- Safaricom Daraja sandbox credentials, registered shortcode/Till/Paybill, public HTTPS callback URL and sandbox test execution; production M-PESA approval.
- Real device testing for offline mode and browser storage lifecycle.
- A documented tax policy for VAT-inclusive/exclusive prices, tax categories, exempt/zero-rated items, rounding, returns and credit notes.
- Verified backup/restore, audit logging, monitoring, and production tenant-isolation test results.
