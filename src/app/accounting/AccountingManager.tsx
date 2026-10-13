"use client";

import { useCallback, useEffect, useState } from "react";
import { Building2, LoaderCircle, Plus, RefreshCw, Wallet } from "lucide-react";

type Supplier = { id: string; name: string; supplier_code: string | null; kra_pin: string | null; is_active: boolean };
type Bill = { id: string; supplier_id: string; supplier_invoice_number: string; bill_date: string; due_date: string | null; status: string; total_amount: number | string; amount_paid: number | string };
type Settlement = { id: string; settlement_reference: string; period_start: string; period_end: string; gross_amount: number | string; fee_amount: number | string; net_amount: number | string; status: string; bank_reference: string | null };
type Payment = { id: string; document_id: string; provider_reference: string | null; amount: number | string; received_amount: number | string; confirmed_at: string; status: string };

export function AccountingManager({ organizationId }: { organizationId: string }) {
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [bills, setBills] = useState<Bill[]>([]);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [showSupplierForm, setShowSupplierForm] = useState(false);
  const [showBillForm, setShowBillForm] = useState(false);
  const [supplierForm, setSupplierForm] = useState({ name: "", code: "", kraPin: "", phone: "", email: "" });
  const [billForm, setBillForm] = useState({ supplierId: "", invoiceNumber: "", billDate: new Date().toISOString().slice(0, 10), dueDate: "", accountCode: "6000", description: "Supplier invoice", netAmount: "", taxAmount: "0" });
  const [paymentBill, setPaymentBill] = useState<Bill | null>(null);
  const [paymentForm, setPaymentForm] = useState({ amount: "", tenderType: "bank_transfer", reference: "" });
  const [settlementForm, setSettlementForm] = useState({ reference: "", periodStart: "", periodEnd: "", grossAmount: "", feeAmount: "0", netAmount: "", bankReference: "" });
  const [selectedSettlementId, setSelectedSettlementId] = useState("");
  const [selectedPaymentIds, setSelectedPaymentIds] = useState<string[]>([]);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [supplierResponse, settlementResponse] = await Promise.all([
        fetch("/api/accounting/suppliers?organizationId=" + encodeURIComponent(organizationId), { cache: "no-store" }),
        fetch("/api/accounting/mpesa-settlements?organizationId=" + encodeURIComponent(organizationId), { cache: "no-store" })
      ]);
      const supplierData = await supplierResponse.json();
      const settlementData = await settlementResponse.json();
      if (!supplierResponse.ok) throw new Error(supplierData.error ?? "Could not load supplier accounts.");
      if (!settlementResponse.ok) throw new Error(settlementData.error ?? "Could not load settlements.");
      setSuppliers(supplierData.suppliers ?? []);
      setBills(supplierData.bills ?? []);
      setSettlements(settlementData.settlements ?? []);
      setPayments(settlementData.payments ?? []);
      if (!selectedSettlementId && settlementData.settlements?.length) setSelectedSettlementId(settlementData.settlements[0].id);
      setError("");
    } catch (e) { setError(e instanceof Error ? e.message : "Could not load accounting workflows."); }
    finally { setLoading(false); }
  }, [organizationId, selectedSettlementId]);
  useEffect(() => { void load(); }, [load]);

  async function submitSupplier(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError(""); setNotice("");
    try {
      const response = await fetch("/api/accounting/suppliers", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ organizationId, action: "create_supplier", name: supplierForm.name, supplierCode: supplierForm.code, kraPin: supplierForm.kraPin, phone: supplierForm.phone, email: supplierForm.email }) });
      const result = await response.json(); if (!response.ok) throw new Error(result.error ?? "Could not create supplier.");
      setSupplierForm({ name: "", code: "", kraPin: "", phone: "", email: "" }); setShowSupplierForm(false); setNotice("Supplier saved."); await load();
    } catch (e) { setError(e instanceof Error ? e.message : "Could not create supplier."); }
    finally { setBusy(false); }
  }

  async function submitBill(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError(""); setNotice("");
    try {
      const response = await fetch("/api/accounting/suppliers", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({
        organizationId, action: "create_bill", supplierId: billForm.supplierId, invoiceNumber: billForm.invoiceNumber,
        billDate: billForm.billDate, dueDate: billForm.dueDate || undefined,
        lines: [{ description: billForm.description, account_code: billForm.accountCode, net_amount: Number(billForm.netAmount), tax_amount: Number(billForm.taxAmount) }]
      }) });
      const result = await response.json(); if (!response.ok) throw new Error(result.error ?? "Could not post supplier bill.");
      setShowBillForm(false); setBillForm({ supplierId: "", invoiceNumber: "", billDate: new Date().toISOString().slice(0, 10), dueDate: "", accountCode: "6000", description: "Supplier invoice", netAmount: "", taxAmount: "0" });
      setNotice("Supplier bill posted to the accounting ledger."); await load();
    } catch (e) { setError(e instanceof Error ? e.message : "Could not post supplier bill."); }
    finally { setBusy(false); }
  }

  async function submitSupplierPayment(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!paymentBill) return; setBusy(true); setError(""); setNotice("");
    try {
      const response = await fetch("/api/accounting/suppliers", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({
        organizationId, action: "pay_bill", billId: paymentBill.id, tenderType: paymentForm.tenderType,
        amount: Number(paymentForm.amount), providerReference: paymentForm.reference || undefined
      }) });
      const result = await response.json(); if (!response.ok) throw new Error(result.error ?? "Could not record supplier payment.");
      setPaymentBill(null); setPaymentForm({ amount: "", tenderType: "bank_transfer", reference: "" }); setNotice("Supplier payment posted."); await load();
    } catch (e) { setError(e instanceof Error ? e.message : "Could not record supplier payment."); }
    finally { setBusy(false); }
  }

  async function submitSettlement(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError(""); setNotice("");
    try {
      const response = await fetch("/api/accounting/mpesa-settlements", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({
        organizationId, action: "record", settlementReference: settlementForm.reference,
        periodStart: new Date(settlementForm.periodStart).toISOString(), periodEnd: new Date(settlementForm.periodEnd).toISOString(),
        grossAmount: Number(settlementForm.grossAmount), feeAmount: Number(settlementForm.feeAmount), netAmount: Number(settlementForm.netAmount),
        bankReference: settlementForm.bankReference || undefined
      }) });
      const result = await response.json(); if (!response.ok) throw new Error(result.error ?? "Could not record settlement.");
      setNotice("Settlement and bank/fee/clearing journal posted. Match its receipts next."); await load();
    } catch (e) { setError(e instanceof Error ? e.message : "Could not record settlement."); }
    finally { setBusy(false); }
  }

  async function matchSettlement() {
    if (!selectedSettlementId || !selectedPaymentIds.length) { setError("Choose a settlement and at least one unmatched payment."); return; }
    setBusy(true); setError(""); setNotice("");
    try {
      const response = await fetch("/api/accounting/mpesa-settlements", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ organizationId, action: "match", settlementId: selectedSettlementId, paymentIds: selectedPaymentIds }) });
      const result = await response.json(); if (!response.ok) throw new Error(result.error ?? "Could not match settlement.");
      const match = result.result as { status?: string; variance?: number; payment_total?: number; gross_amount?: number };
      setNotice(match.status === "variance" ? "Settlement variance: gross KES " + match.gross_amount + ", confirmed receipts KES " + match.payment_total + ", variance KES " + match.variance + ". No receipt matches were saved." : "Settlement matched to confirmed M-PESA receipts.");
      setSelectedPaymentIds([]); await load();
    } catch (e) { setError(e instanceof Error ? e.message : "Could not match settlement."); }
    finally { setBusy(false); }
  }

  const money = (value: number | string) => "KES " + Number(value).toLocaleString("en-KE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const supplierName = (id: string) => suppliers.find(s => s.id === id)?.name ?? "Supplier";
  return <>
    <div className="catalog-toolbar"><p className="muted">Supplier bills, payments and settlement journals are recorded server-side and scoped to this workspace.</p><button className="provider-connect" type="button" onClick={() => void load()} disabled={loading || busy}><RefreshCw size={15}/> Refresh</button><button className="primary-button" type="button" onClick={() => setShowSupplierForm(v => !v)}><Plus size={16}/> Add supplier</button><button className="primary-button" type="button" onClick={() => setShowBillForm(v => !v)} disabled={!suppliers.length}><Plus size={16}/> New bill</button></div>
    {error && <p className="form-feedback error-feedback" role="alert">{error}</p>}
    {notice && <p className="form-feedback" role="status">{notice}</p>}
    {showSupplierForm && <form className="product-form" onSubmit={submitSupplier}><h2>New supplier</h2><div className="product-form-grid">
      <label className="payment-form-label">Supplier name<input required minLength={2} maxLength={200} value={supplierForm.name} onChange={e => setSupplierForm({ ...supplierForm, name: e.target.value })}/></label>
      <label className="payment-form-label">Supplier code<input maxLength={80} value={supplierForm.code} onChange={e => setSupplierForm({ ...supplierForm, code: e.target.value })}/></label>
      <label className="payment-form-label">KRA PIN<input maxLength={30} value={supplierForm.kraPin} onChange={e => setSupplierForm({ ...supplierForm, kraPin: e.target.value })}/></label>
      <label className="payment-form-label">Phone<input maxLength={40} value={supplierForm.phone} onChange={e => setSupplierForm({ ...supplierForm, phone: e.target.value })}/></label>
      <label className="payment-form-label">Email<input type="email" value={supplierForm.email} onChange={e => setSupplierForm({ ...supplierForm, email: e.target.value })}/></label>
    </div><div className="modal-actions"><button className="provider-cancel" type="button" onClick={() => setShowSupplierForm(false)}>Cancel</button><button className="provider-connect primary" disabled={busy}>{busy ? "Saving…" : "Save supplier"}</button></div></form>}
    {showBillForm && <form className="product-form" onSubmit={submitBill}><h2>Post supplier bill</h2><div className="product-form-grid">
      <label className="payment-form-label">Supplier<select required value={billForm.supplierId} onChange={e => setBillForm({ ...billForm, supplierId: e.target.value })}><option value="">Choose supplier</option>{suppliers.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}</select></label>
      <label className="payment-form-label">Supplier invoice number<input required maxLength={100} value={billForm.invoiceNumber} onChange={e => setBillForm({ ...billForm, invoiceNumber: e.target.value })}/></label>
      <label className="payment-form-label">Bill date<input required type="date" value={billForm.billDate} onChange={e => setBillForm({ ...billForm, billDate: e.target.value })}/></label>
      <label className="payment-form-label">Due date<input type="date" min={billForm.billDate} value={billForm.dueDate} onChange={e => setBillForm({ ...billForm, dueDate: e.target.value })}/></label>
      <label className="payment-form-label">Expense / inventory account<select value={billForm.accountCode} onChange={e => setBillForm({ ...billForm, accountCode: e.target.value })}><option value="1200">Inventory control</option><option value="6000">Rent expense</option><option value="6100">Utilities and communications</option></select></label>
      <label className="payment-form-label">Line description<input required maxLength={500} value={billForm.description} onChange={e => setBillForm({ ...billForm, description: e.target.value })}/></label>
      <label className="payment-form-label">Net amount (KES)<input required type="number" min="0.01" step="0.01" value={billForm.netAmount} onChange={e => setBillForm({ ...billForm, netAmount: e.target.value })}/></label>
      <label className="payment-form-label">Input tax (KES)<input required type="number" min="0" step="0.01" value={billForm.taxAmount} onChange={e => setBillForm({ ...billForm, taxAmount: e.target.value })}/></label>
    </div><p className="muted">Use only the account/tax treatment approved for the actual supplier document. Input tax must be reviewed before tax reporting.</p><div className="modal-actions"><button className="provider-cancel" type="button" onClick={() => setShowBillForm(false)}>Cancel</button><button className="provider-connect primary" disabled={busy}>{busy ? "Posting…" : "Post bill"}</button></div></form>}
    {paymentBill && <form className="product-form" onSubmit={submitSupplierPayment}><h2>Pay {paymentBill.supplier_invoice_number} · {supplierName(paymentBill.supplier_id)}</h2><p className="muted">Outstanding: {money(Number(paymentBill.total_amount) - Number(paymentBill.amount_paid))}</p><div className="product-form-grid">
      <label className="payment-form-label">Amount (KES)<input required type="number" min="0.01" max={Number(paymentBill.total_amount) - Number(paymentBill.amount_paid)} step="0.01" value={paymentForm.amount} onChange={e => setPaymentForm({ ...paymentForm, amount: e.target.value })}/></label>
      <label className="payment-form-label">Tender<select value={paymentForm.tenderType} onChange={e => setPaymentForm({ ...paymentForm, tenderType: e.target.value })}><option value="bank_transfer">Bank transfer</option><option value="cash">Cash</option><option value="mpesa">M-PESA (outgoing)</option><option value="other">Other</option></select></label>
      <label className="payment-form-label">Provider / bank reference<input maxLength={120} value={paymentForm.reference} onChange={e => setPaymentForm({ ...paymentForm, reference: e.target.value })} placeholder="Required for M-PESA"/></label>
    </div><div className="modal-actions"><button className="provider-cancel" type="button" onClick={() => setPaymentBill(null)}>Cancel</button><button className="provider-connect primary" disabled={busy}>{busy ? "Posting…" : "Record payment"}</button></div></form>}
    <section className="catalog-table-wrap"><h2 className="section-title"><Building2 size={17}/> Suppliers and payables</h2><div className="catalog-table-scroll"><table><thead><tr><th>SUPPLIER / INVOICE</th><th>BILL DATE</th><th>DUE DATE</th><th>STATUS</th><th>TOTAL</th><th>PAID</th><th>BALANCE</th><th>ACTION</th></tr></thead><tbody>
      {loading ? <tr><td colSpan={8} className="empty-catalog">Loading supplier accounts…</td></tr> : bills.length ? bills.map(b => <tr key={b.id}><td><strong>{supplierName(b.supplier_id)}</strong><div className="muted">{b.supplier_invoice_number}</div></td><td>{new Date(b.bill_date).toLocaleDateString("en-KE")}</td><td>{b.due_date ? new Date(b.due_date).toLocaleDateString("en-KE") : "—"}</td><td><span className={b.status === "paid" ? "status completed" : "status pending"}>{b.status}</span></td><td>{money(b.total_amount)}</td><td>{money(b.amount_paid)}</td><td>{money(Number(b.total_amount) - Number(b.amount_paid))}</td><td>{b.status !== "paid" && b.status !== "void" ? <button className="provider-connect primary" type="button" onClick={() => { setPaymentBill(b); setPaymentForm({ amount: String(Number(b.total_amount) - Number(b.amount_paid)), tenderType: "bank_transfer", reference: "" }); }}>Pay bill</button> : "—"}</td></tr>) : <tr><td colSpan={8} className="empty-catalog">No supplier bills recorded.</td></tr>}
    </tbody></table></div><div className="table-footer"><span>{suppliers.length} suppliers · {bills.length} bills</span><span>Supplier bills post into the general ledger.</span></div></section>
    <section className="product-form"><h2><Wallet size={17}/> M-PESA settlement reconciliation</h2><p className="muted">Record the actual settlement statement first, then match confirmed customer receipts. Gross minus fees must equal net.</p>
      <form onSubmit={submitSettlement}><div className="product-form-grid">
        <label className="payment-form-label">Settlement reference<input required maxLength={120} value={settlementForm.reference} onChange={e => setSettlementForm({ ...settlementForm, reference: e.target.value })}/></label>
        <label className="payment-form-label">Period start<input required type="datetime-local" value={settlementForm.periodStart} onChange={e => setSettlementForm({ ...settlementForm, periodStart: e.target.value })}/></label>
        <label className="payment-form-label">Period end<input required type="datetime-local" value={settlementForm.periodEnd} onChange={e => setSettlementForm({ ...settlementForm, periodEnd: e.target.value })}/></label>
        <label className="payment-form-label">Gross receipts (KES)<input required type="number" min="0.01" step="0.01" value={settlementForm.grossAmount} onChange={e => setSettlementForm({ ...settlementForm, grossAmount: e.target.value })}/></label>
        <label className="payment-form-label">Fees (KES)<input required type="number" min="0" step="0.01" value={settlementForm.feeAmount} onChange={e => setSettlementForm({ ...settlementForm, feeAmount: e.target.value })}/></label>
        <label className="payment-form-label">Net bank deposit (KES)<input required type="number" min="0.01" step="0.01" value={settlementForm.netAmount} onChange={e => setSettlementForm({ ...settlementForm, netAmount: e.target.value })}/></label>
        <label className="payment-form-label">Bank reference<input maxLength={120} value={settlementForm.bankReference} onChange={e => setSettlementForm({ ...settlementForm, bankReference: e.target.value })}/></label>
      </div><div className="modal-actions"><button className="provider-connect primary" disabled={busy}>{busy ? "Posting…" : "Record settlement"}</button></div></form>
      <div className="catalog-table-scroll"><table><thead><tr><th>SETTLEMENT</th><th>PERIOD END</th><th>GROSS</th><th>FEES</th><th>NET</th><th>STATUS</th></tr></thead><tbody>{settlements.map(s => <tr key={s.id}><td>{s.settlement_reference}</td><td>{new Date(s.period_end).toLocaleString("en-KE")}</td><td>{money(s.gross_amount)}</td><td>{money(s.fee_amount)}</td><td>{money(s.net_amount)}</td><td><span className={s.status === "matched" ? "status completed" : "status pending"}>{s.status}</span></td></tr>)}{!settlements.length && <tr><td colSpan={6} className="empty-catalog">No settlement statements yet.</td></tr>}</tbody></table></div>
      <h3>Match confirmed receipts</h3><div className="product-form-grid"><label className="payment-form-label">Settlement<select value={selectedSettlementId} onChange={e => setSelectedSettlementId(e.target.value)}><option value="">Choose settlement</option>{settlements.filter(s => s.status !== "matched").map(s => <option key={s.id} value={s.id}>{s.settlement_reference} · {s.status} · {money(s.gross_amount)}</option>)}</select></label></div>
      <div className="catalog-table-scroll"><table><thead><tr><th>SELECT</th><th>PROVIDER RECEIPT</th><th>CONFIRMED</th><th>AMOUNT</th></tr></thead><tbody>{payments.map(p => <tr key={p.id}><td><input type="checkbox" checked={selectedPaymentIds.includes(p.id)} onChange={e => setSelectedPaymentIds(prev => e.target.checked ? [...prev,p.id] : prev.filter(id => id !== p.id))}/></td><td>{p.provider_reference ?? p.id}</td><td>{new Date(p.confirmed_at).toLocaleString("en-KE")}</td><td>{money(p.received_amount)}</td></tr>)}{!payments.length && <tr><td colSpan={4} className="empty-catalog">No unmatched confirmed invoice M-PESA receipts.</td></tr>}</tbody></table></div>
      <div className="modal-actions"><button className="provider-connect primary" type="button" disabled={busy || !selectedSettlementId || !selectedPaymentIds.length} onClick={() => void matchSettlement()}>{busy ? <><LoaderCircle size={15}/> Matching…</> : "Match selected receipts"}</button></div>
    </section>
  </>;
}
