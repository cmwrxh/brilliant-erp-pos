# SafariPOS Accounting Policy and CPA Review Pack

**Status:** Draft for Kenyan CPA review; not an approved accounting policy.
**Scope:** Kenyan retail/duka and wholesale pilot; KES functional currency; accrual accounting; perpetual inventory; moving weighted-average cost per product and location.
**Release rule:** SafariPOS must not present a formal P&L or balance sheet until the ledger acceptance suite passes. Any interim profit metric must be labelled **estimate, not ledger-verified**.
**Important:** Examples are design proposals, not tax advice. The CPA must confirm account mapping, VAT/eTIMS treatment and cut-off before production use.

## 1. Default chart of accounts proposal

Each business receives its own editable copy of this template. Account codes are stable within that business. Account type, normal balance, control-account flag and system role are protected from unsafe edits. Deactivating an account must not remove history. Each control account maps to the relevant subledger.

| Code | Account | Type / purpose |
|---|---|---|
| 1000 | Cash on hand | Asset; by location/till |
| 1010 | Bank current account | Asset; per bank account |
| 1020 | M-PESA clearing | Asset; receipts less fees, refunds and settlements |
| 1030 | Card/payment-provider clearing | Asset; provider receivable |
| 1100 | Accounts receivable control | Asset; customer subledger |
| 1110 | Allowance for doubtful debts | Contra-asset; optional |
| 1200 | Inventory control | Asset; reconciles to valuation subledger |
| 1210 | Input VAT recoverable | Asset; only where recoverable |
| 1300 | Prepayments | Asset |
| 1500 | Property, plant and equipment | Asset; asset register |
| 1590 | Accumulated depreciation | Contra-asset |
| 2000 | Accounts payable control | Liability; supplier subledger |
| 2100 | Output VAT payable | Liability |
| 2110 | VAT control/settlement | Liability/clearing; CPA to confirm |
| 2200 | Accrued expenses | Liability |
| 2210 | Salaries and statutory deductions payable | Liability |
| 2300 | Customer deposits/deferred revenue | Liability |
| 2400 | Loans payable | Liability |
| 3000 | Owner capital/share capital | Equity; entity-specific |
| 3100 | Owner contributions/additional paid-in capital | Equity; entity-specific |
| 3200 | Owner drawings | Equity contra-account; sole proprietor only |
| 3300 | Retained earnings | Equity; accumulated prior results |
| 3900 | Current-year earnings | Equity/reporting close |
| 4000 | Retail sales revenue | Revenue |
| 4010 | Wholesale sales revenue | Revenue; optional |
| 4020 | Sales returns and allowances | Contra-revenue |
| 4030 | Sales discounts | Contra-revenue |
| 4100 | Other operating income | Revenue |
| 5000 | Cost of goods sold | Expense |
| 5010 | Inventory expiry/write-off | Expense |
| 5020 | Stocktake shrinkage/adjustment | Expense or gain |
| 6000 | Rent expense | Expense |
| 6010 | Salaries and wages | Expense |
| 6020 | Employer payroll costs | Expense |
| 6100 | Utilities and communications | Expense |
| 6110 | Transport and delivery | Expense |
| 6120 | Payment processing/M-PESA fees | Expense |
| 6130 | Repairs and maintenance | Expense |
| 6200 | Depreciation expense | Expense |
| 6300 | Bad debt expense | Expense |
| 6400 | Cash over/short | Expense or income |
| 6500 | Income tax expense | Expense; CPA-reviewed |
| 7000 | Gain/loss on asset disposal | Other income/expense |

The CPA must approve company-versus-sole-proprietor equity, VAT settlement, payroll/statutory liabilities, depreciation classes and tax presentation. Businesses may add accounts but cannot delete accounts referenced by posted entries or change historical account meaning.

## 2. Posting architecture and invariants

1. Only verified POS, inventory, payments, supplier, expense, fixed-asset, tax and reconciliation events may request posting. Browser clients never write journal lines directly.
2. A trusted server-side PostgreSQL posting function runs in one transaction. It validates tenant membership/role, source state, source-document uniqueness, period status, tax/account mapping and subledger totals; then inserts header, lines, source linkage and audit record atomically.
3. A unique idempotency key on organization + source type + source ID + posting purpose prevents duplicate journals. A retry returns the original result, not another journal.
4. Every posted journal has at least two lines, positive amounts, one business/currency and equal debit/credit totals at currency precision. Client roles cannot directly insert, update or delete posted journal rows.
5. Posted entries and lines are immutable. Corrections create separately numbered reversals linked to the original and a corrected journal if required. Keep actor, timestamp, reason, source and correlation IDs.
6. Closed periods reject ordinary backdated postings. Reopening requires privileged permission, reason and audit record. Close checks trial balance and all subledger reconciliations. Year-end earnings close to retained earnings without rewriting old journals.
7. Each business has its own chart, fiscal calendar, accounting basis and costing method. Basis and costing lock at first posted journal; changing either later requires an audited, CPA-approved conversion.
8. Use fixed-precision numeric/decimal arithmetic, never floating-point money. Store accounting date separately from event timestamp.
9. Reports derive from posted ledger lines plus explicitly reconciled subledgers. Until tests pass, hide formal P&L and balance sheet and label dashboard profit as an estimate.
10. RLS applies to all accounting/subledger tables, audit records, exports and RPCs. Service-role calls must validate organization scope too.

## 3. Posting rules

Amounts below are KES. VAT examples assume an illustrative 16% standard rate and recoverable input VAT; the CPA must verify current rates and each transaction's treatment. For VAT-inclusive prices, extract the taxable base instead of adding VAT twice.

### A. Cash sale with VAT and cost of goods
For net sale 1,000, output VAT 160 and cost 600:
- Dr Cash 1,160; Cr Sales revenue 1,000; Cr Output VAT payable 160.
- Dr Cost of goods sold 600; Cr Inventory 600.

### B. Credit sale
- Dr Accounts receivable 1,160; Cr Sales revenue 1,000; Cr Output VAT payable 160.
- Dr Cost of goods sold 600; Cr Inventory 600.
AR must match the customer invoice subledger.

### C. Customer pays later
For settlement of the 1,160 invoice:
- Dr Cash/Bank/M-PESA clearing 1,160; Cr Accounts receivable 1,160.
Allocate to invoice(s); overpayments remain customer credit/unapplied receipts, not revenue.

### D. Supplier purchase on credit
For inventory 1,000 plus 160 recoverable input VAT:
- Dr Inventory 1,000; Dr Input VAT recoverable 160; Cr Accounts payable 1,160.
Non-recoverable VAT is treated per CPA policy. Landed costs are allocated only under the approved costing policy.

### E. Refund / credit note
For full credit note against taxable sale:
- Dr Sales returns 1,000; Dr Output VAT payable 160; Cr Cash/Bank/M-PESA clearing or AR 1,160.
If the goods physically return in saleable condition: Dr Inventory 600; Cr COGS 600. Do not restore saleable stock if goods were not returned or are unsaleable. Link the credit note to the original invoice and eTIMS workflow; never fabricate a credit note for an invoice issued by another system.

### F. M-PESA fee and settlement
For a KSh 23 fee:
- Dr Payment processing fees 23; Cr M-PESA clearing 23.
For KSh 1,137 net settlement of gross 1,160 less fee 23, if fee was not already posted:
- Dr Bank 1,137; Dr Payment processing fees 23; Cr M-PESA clearing 1,160.
Use one consistent workflow so fees are not double-booked. Reconcile provider reference, gross, fee, refund and net deposit.

### G. Expired stock
For expired inventory with carrying cost 600:
- Dr Inventory expiry/write-off expense 600; Cr Inventory 600.
Record product, batch/expiry where relevant, location, quantity, cost, reason, actor and approval. Pharmacy batch tracking/expiry is separate from core valuation and needs regulatory review.

### H. Expenses and accruals
Current-month rent paid 20,000: Dr Rent expense 20,000; Cr Bank/Cash 20,000. Advance rent: Dr Prepayments; Cr Bank, then expense over covered months. Unpaid salary: Dr Salaries expense; Cr Salaries payable; on payment Dr Salaries payable; Cr Bank. Record payroll deductions using approved calculations.

### I. Opening balances
At controlled cutover, post a balanced opening journal with supporting schedules. Import AR/AP invoice-by-invoice and opening inventory by product/location/quantity/cost so subledgers reconcile. CPA must approve balancing equity. No unexplained plug account.

### J. Owner capital, drawings and company distributions
Sole proprietor contribution: Dr Cash/Bank; Cr Owner capital. Sole proprietor withdrawal: Dr Owner drawings; Cr Cash/Bank. A limited company must not use drawings as a substitute for payroll, director loan, dividend or other lawful transaction; classify per legal records and CPA advice.

### K. Cash-up over/short
Till is 100 short: Dr Cash over/short expense 100; Cr Cash 100. Till is 100 over: Dr Cash 100; Cr Cash over/short income 100. Store expected/count cash, safe drops, refunds, shift/cashier, reviewer and threshold; investigate material or repeated differences.

### L. Stocktake adjustment
Two units missing at weighted-average cost 300: Dr Stocktake shrinkage 600; Cr Inventory 600. For excess stock use approved inventory gain/adjustment account. Both quantity movement and valuation require reason code, approver and journal reference.

### M. Fixed assets and depreciation
Qualifying equipment 120,000 plus 19,200 hypothetical recoverable VAT on credit: Dr PPE 120,000; Dr Input VAT 19,200; Cr AP 139,200. Monthly depreciation 2,000: Dr Depreciation expense 2,000; Cr Accumulated depreciation 2,000. CPA sets capitalization threshold, useful life, residual value, method and tax depreciation. Disposal removes asset cost/accumulated depreciation and records proceeds and gain/loss.

### N. Bank reconciliation and transfers
Transfer 50,000 from till to bank: Dr Bank 50,000; Cr Cash 50,000. Bank charges debit fee expense and credit bank. Unmatched statement lines remain in a review queue; do not guess a posting. Reconciliation marks are audited and do not rewrite source statements.

### O. M-PESA receipts, refunds and clearing
For a verified receipt on a credit invoice: Dr M-PESA clearing; Cr AR. For a new cash sale, sale revenue/VAT is posted once and the tender debits clearing. Fees debit fee expense/credit clearing. Settlement debits Bank for net deposit and clearing for gross; if fees were separately posted, do not debit them again. Refunds use a linked credit note and correct clearing/bank/customer account. A callback must not create a second sale; match provider transaction ID, amount, currency, merchant and source document idempotently.

### P. VAT codes
Each product/service line references effective-dated tax code (standard, zero-rated, exempt, plus CPA-approved special codes). Snapshot code, rate, base and amount on invoice and journal. Output VAT is a liability; recoverable input VAT an asset. Zero-rated and exempt are distinct. Mixed-rate invoices calculate per line using approved rounding. Credit notes reverse the original tax, not today's rate.

### Q. Weighted-average cost and negative stock
Moving average per product/location = (prior on-hand value + receipt value + approved landed costs) / new on-hand quantity. Sale COGS uses average cost at posting order. Returns restore original cost when known; transfers carry source cost. Default negative stock policy is **block**. If owner enables **allow with warning**, flag for review and use a CPA-approved provisional-cost and subsequent cost-difference process. Lock costing method after first posting. Pharmacy batch/expiry controls are additional records.

### R. Period close and retained earnings
Close only after journals balance, bank/M-PESA and subledgers reconcile, VAT exceptions are reviewed and suspense balances resolved. Lock period and record actor/time. Year-end close revenue/expense to current-year earnings and retained earnings under entity policy; never delete old journals. Reopen or adjust only with authorized audit trail.

### S. AR/AP and ageing
Invoices establish AR/AP and source journals. Payments allocate to invoices; credit notes reduce linked balances. Ageing uses posted open items and due dates; totals equal control accounts. Show unapplied cash and supplier credits separately rather than silently netting unrelated counterparties.

## 4. Ledger-derived reports and exports

Required: trial balance, general ledger, journal register, P&L and balance sheet after acceptance, AR/AP ageing, inventory valuation, VAT summary, cash-up and payment/bank/M-PESA reconciliation. CSV, XLSX and PDF exports must include business name, report/period or as-of date, currency, generated timestamp, account code/name, source type/ID/reference and filters. Exports must match the same in-app report cutoff exactly.

## 5. Sample month for automated acceptance

Use an isolated test business, one retail location, KES, opening inventory 10 units at 300 (3,000), hypothetical standard VAT 16%, opening cash 50,000, bank 100,000, AR 11,600 and AP 5,800. These are test fixtures, not tax-rate assertions.

| Day | Source event | Expected outcome |
|---|---|---|
| 1 | Import opening cash, bank, inventory, AR/AP invoices and equity | Balanced opening journal; subledgers and stock valuation reconcile |
| 2 | Buy 20 units at 350 each plus hypothetical recoverable VAT on credit | Inventory +7,000; input VAT and AP increase |
| 3 | Cash sale 2 units at 500 net each plus VAT | Cash +1,160; revenue 1,000; output VAT 160; COGS at weighted average; stock -2 |
| 4 | Credit sale 3 units at 500 net each plus VAT | AR +1,740; revenue 1,500; output VAT 240; COGS; stock -3 |
| 5 | Customer pays Day 4 invoice via M-PESA, 1,740 | Clearing +1,740; AR -1,740; no duplicate revenue |
| 6 | Fee 35, net settlement 1,705 | Fee 35; bank +1,705; clearing reconciles to zero for that settlement |
| 7 | Rent invoice 20,000 unpaid | Rent expense and AP increase |
| 8 | Pay 5,800 opening supplier invoice | Bank/AP decrease |
| 10 | Credit note for one saleable unit from Day 4, net 500 plus VAT | Returns 500; output VAT reversal 80; customer credit/refund 580; stock restored at original cost |
| 12 | Stocktake finds one missing unit | Stock and inventory value decrease; shrinkage expense; approval/reference retained |
| 15 | Till is 100 short | Cash and cash-over/short expense posted; review flag |
| 20 | Buy equipment 120,000 plus hypothetical recoverable VAT on credit | PPE/input VAT debit; AP credit |
| 30 | Depreciation 2,000; accrue unpaid salary 15,000; close month | Depreciation and salary expense; salary payable; reconciliations; period lock |

### Automated assertions
1. Each posted journal and the trial balance balance exactly.
2. Replaying any source event never duplicates a journal.
3. Inventory valuation equals Inventory control after each stock event and at month end.
4. Customer open items equal AR; supplier open items equal AP.
5. M-PESA gross receipts, fees, refunds and net settlements reconcile to clearing/provider statements.
6. Reversals retain original journal, source and audit history.
7. Ordinary users cannot backdate into a closed period.
8. A second tenant cannot read, post, export or infer the first tenant's records.
9. CSV/XLSX/PDF exports match the corresponding in-app report.
10. eTIMS credit note references the original SafariPOS invoice; rejected responses remain visible/retryable without duplicate ledger posting.

## 6. CPA sign-off checklist and decisions

- [ ] Approve chart and entity-specific equity treatment.
- [ ] Approve accrual recognition and revenue/tax point rules.
- [ ] Confirm VAT codes, recoverability, rounding, credit notes and eTIMS mapping.
- [ ] Approve weighted-average costing, landed costs, returns/transfers and any provisional negative-stock policy.
- [ ] Approve opening balances, AR/AP cutover and inventory evidence.
- [ ] Approve fixed-asset threshold, useful lives, depreciation and disposals.
- [ ] Approve payroll/statutory liabilities, cash over/short thresholds and period close.
- [ ] Review sample-month journals, reconciliations, audit trail and accountant exports.
- [ ] Sign off before enabling formal statements or calling the product a full ERP.

**Recommended defaults:** accrual; perpetual inventory; moving weighted average per product/location; negative stock blocked; closed periods locked; posted journals immutable; one editable account template per business.

**Dependencies:** current KRA eTIMS specifications, taxpayer onboarding and any integrator certification; Daraja sandbox/production access; CPA approval of tax/accounting rules. Never put production secrets in this document or Git.
