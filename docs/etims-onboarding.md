# KRA eTIMS integration onboarding

Official KRA guidance: https://www.kra.go.ke/business/etims-electronic-tax-invoice-management-system/learn-about-etims/etims-system-to-system-integration

## Start on the taxpayer side

1. Sign in to the KRA eTIMS taxpayer portal at https://etims.kra.go.ke/ and confirm the taxpayer PIN and business details for the business that will issue invoices.
2. Open the **System-to-System Integration** section and review the current OSCU and VSCU specifications, sandbox sign-up guide, and Trader Invoicing System technical specification.
3. Choose a path with KRA:
   - **OSCU** is intended for systems that are online when invoicing.
   - **VSCU** is intended for bulk invoicing and systems that are not always online. This is the option to discuss first for a POS that must keep operating during network interruptions.
4. Start the sandbox/self-integration process and obtain the current API specification, sandbox access and taxpayer/device initialization details. Do not send KRA PINs, passwords or API secrets in this repository or in chat.
5. Ask KRA whether Brilliant Unicorn Ltd must apply as a third-party software integrator, as the product is intended for multiple customer businesses. KRA's published process includes development, testing, vetting and certification for third-party integrators and self-integrating taxpayers.
6. Ask for the current process and required documents for vendor/integrator certification and whether each customer taxpayer needs separate onboarding/initialization and credentials.

## Product-side implementation still required

The database has an eTIMS invoice outbox with invoice/credit-note/reversal types, buyer PIN field, status, response audit fields and retry metadata. It does **not** yet transmit invoices to KRA. Once KRA supplies the applicable current spec and sandbox access, implementation must cover:

- taxpayer/branch/device initialization and reference-data synchronization;
- tax-category/item mapping and Kenya-specific invoice payload;
- durable, retry-safe invoice submission with KRA response/control-unit receipt fields;
- buyer PIN capture and validation when supplied;
- credit notes tied to the original invoice issued by this solution, and approved reversal rules;
- accepted/rejected/retryable/requires-review status, reconciliation reports and audit history;
- sandbox test cases, certification/vetting, and approval before live invoicing.

KRA states that credit notes can only be generated from the solution that issued the original invoice. Do not generate a credit note for an invoice that originated in a different solution.

## Decision needed

When KRA confirms your onboarding path, record whether we should target OSCU or VSCU first and provide only non-secret technical requirements/specifications. Keep production issuance disabled until certification and a reviewed live release.
