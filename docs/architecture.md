# Brilliant ERP/POS architecture

## Product direction
Brilliant ERP is a multi-tenant B2B SaaS for Kenyan businesses. The first workflow targets fast-moving retail and dukas, with a domain model that can grow into wholesale, hospitality, and service businesses without mixing their operational rules.

## Initial stack
- Web application: Next.js App Router, React, TypeScript.
- Data platform: Supabase PostgreSQL and Supabase Auth.
- Deployment target: Coolify, with environment-specific secrets configured in the hosting dashboard.
- Payments: provider abstraction; M-Pesa integration is planned but not enabled.
- Locale defaults: Kenya (KE), Kenyan shilling (KES), Africa/Nairobi timezone.

## Initial modules
1. Identity, organizations, memberships, roles and permissions.
2. Locations / branches.
3. Product catalogue, SKU/barcode and pricing.
4. Inventory balances and auditable stock movements.
5. POS checkout, receipts, sale lines, tenders and reversals.
6. Customers and supplier records.
7. Reporting, tax configuration and export.
8. Integrations: M-Pesa, notifications and accounting exports.

## Tenant isolation
Every tenant-owned row carries an organization identifier. Related records use composite foreign keys where useful to prevent cross-organization references. Row Level Security is enabled in the initial migration. Application code must never rely on client-side filtering as an authorization boundary.

Membership provisioning, organization creation, role changes, stock movements, checkout finalization, refunds and payment webhooks require reviewed server-side transactional functions before production. Never expose the Supabase service-role key to a browser.

## POS invariants before production
- Checkout finalization is atomic and idempotent.
- Completed sales have immutable line-item snapshots and payment records.
- Stock changes only through a transactional movement ledger, not arbitrary client updates.
- Payment callbacks are authenticated, idempotent, reconciled and auditable.
- Voids/refunds create reversal records and never erase financial history.
- Money uses fixed-precision decimal database types and explicit currency codes.
- Tax behavior must be validated against current Kenyan requirements before launch.
- A branch and cashier must be authorized for the organization on every write.

## Delivery sequence
1. Foundation and tenant-aware schema.
2. Authentication, organization onboarding and membership provisioning.
3. Product and branch management.
4. Inventory movement ledger and receiving.
5. POS basket, transactional checkout and receipt.
6. Cash/M-Pesa payment reconciliation.
7. Reports, audit log, tax configuration and exports.
8. Automated tenant-isolation, permission, concurrency and recovery tests.

## Current status
The dashboard is a static interface preview using sample data. It is not connected to Supabase and its controls do not perform real business operations yet. The database migration is a starting point for review, not a production-ready accounting or tax implementation.
