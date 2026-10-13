"use client";

import { useCallback, useEffect, useState } from "react";
import { FileText, LoaderCircle, Plus, Send } from "lucide-react";

type Invoice = {
  id: string; document_number: string; status: string; customer_id: string | null;
  location_id: string | null; currency_code: string; subtotal: number | string;
  tax_total: number | string; grand_total: number | string; amount_paid: number | string;
  balance_due: number | string; due_at: string | null; created_at: string;
};
type Customer = { id: string; name: string };
type Product = { id: string; name: string; sku: string; selling_price: number; tax_rate: number };
type Location = { id: string; name: string };

export function InvoiceManager({ organizationId, customers, products, locations }: {
  organizationId: string; customers: Customer[]; products: Product[]; locations: Location[];
}) {
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [mpesaPhone, setMpesaPhone] = useState("");
  const [manualPaymentFor, setManualPaymentFor] = useState<Invoice | null>(null);
  const [paymentAmount, setPaymentAmount] = useState("");
  const [paymentTender, setPaymentTender] = useState("cash");
  const [paymentReference, setPaymentReference] = useState("");
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ documentNumber: "", customerId: "", locationId: locations[0]?.id ?? "", dueAt: "", productId: "", quantity: "1", discountAmount: "0" });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch("/api/invoices?organizationId=" + encodeURIComponent(organizationId), { cache: "no-store" });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Could not load invoices.");
      setInvoices(result.invoices ?? []);
      setError("");
    } catch (e) { setError(e instanceof Error ? e.message : "Could not load invoices."); }
    finally { setLoading(false); }
  }, [organizationId]);
  useEffect(() => { void load(); }, [load]);

  async function createDraft(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError("");
    try {
      const response = await fetch("/api/invoices", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          organizationId, documentNumber: form.documentNumber, customerId: form.customerId,
          locationId: form.locationId, dueAt: new Date(form.dueAt + "T23:59:59+03:00").toISOString(),
          items: [{ productId: form.productId, quantity: Number(form.quantity), discountAmount: Number(form.discountAmount) }]
        })
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Could not create invoice draft.");
      setShowForm(false);
      setForm({ documentNumber: "", customerId: "", locationId: locations[0]?.id ?? "", dueAt: "", productId: "", quantity: "1", discountAmount: "0" });
      await load();
    } catch (e) { setError(e instanceof Error ? e.message : "Could not create invoice draft."); }
    finally { setBusy(false); }
  }

  async function issue(invoice: Invoice) {
    setBusy(true); setError("");
    try {
      const response = await fetch("/api/invoices/issue", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ organizationId, documentId: invoice.id })
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Could not issue invoice.");
      setError("Invoice issued to the internal ledger. eTIMS status is queued, not submitted or accepted.");
      await load();
    } catch (e) { setError(e instanceof Error ? e.message : "Could not issue invoice."); }
    finally { setBusy(false); }
  }

  async function requestMpesa(invoice: Invoice) {
    if (!mpesaPhone.trim()) { setError("Enter the customer phone number before requesting M-PESA STK Push."); return; }
    setBusy(true); setError("");
    try {
      const response = await fetch("/api/invoices/mpesa/initialize", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ organizationId, documentId: invoice.id, phone: mpesaPhone.trim() })
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Could not request M-PESA payment.");
      setError("STK prompt requested for " + invoice.document_number + ". The invoice will update only after Daraja confirms payment.");
    } catch (e) { setError(e instanceof Error ? e.message : "Could not request M-PESA payment."); }
    finally { setBusy(false); }
  }

  async function recordManualPayment(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!manualPaymentFor) return;
    setBusy(true); setError("");
    try {
      const response = await fetch("/api/invoices/payment", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          organizationId, documentId: manualPaymentFor.id, tenderType: paymentTender,
          amount: Number(paymentAmount), providerReference: paymentReference.trim() || undefined
        })
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Could not record payment.");
      setManualPaymentFor(null); setPaymentAmount(""); setPaymentReference("");
      await load();
    } catch (e) { setError(e instanceof Error ? e.message : "Could not record payment."); }
    finally { setBusy(false); }
  }

  const money = (value: number | string) => "KES " + Number(value).toLocaleString("en-KE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return <>
    <div className="catalog-toolbar"><p className="muted">Tax-code mapping and KRA acceptance remain release gates. Issuing a commercial invoice does not mean eTIMS accepted it.</p><label className="payment-form-label">M-PESA phone<input value={mpesaPhone} onChange={e => setMpesaPhone(e.target.value)} placeholder="0712345678" maxLength={30}/></label><button className="primary-button" type="button" onClick={() => setShowForm(v => !v)} disabled={!customers.length || !products.length || !locations.length}><Plus size={16}/> New draft</button></div>
    {error && <p className="form-feedback error-feedback" role="alert">{error}</p>}
    {showForm && <form className="product-form" onSubmit={createDraft}>
      <h2>New invoice draft</h2>
      <div className="product-form-grid">
        <label className="payment-form-label">Invoice number<input required maxLength={80} value={form.documentNumber} onChange={e => setForm({ ...form, documentNumber: e.target.value })} placeholder="INV-2026-0001"/></label>
        <label className="payment-form-label">Customer<select required value={form.customerId} onChange={e => setForm({ ...form, customerId: e.target.value })}><option value="">Choose customer</option>{customers.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
        <label className="payment-form-label">Branch<select required value={form.locationId} onChange={e => setForm({ ...form, locationId: e.target.value })}>{locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select></label>
        <label className="payment-form-label">Due date<input required type="date" value={form.dueAt} onChange={e => setForm({ ...form, dueAt: e.target.value })} min={new Date().toISOString().slice(0, 10)}/></label>
        <label className="payment-form-label">Product<select required value={form.productId} onChange={e => setForm({ ...form, productId: e.target.value })}><option value="">Choose product</option>{products.map(p => <option key={p.id} value={p.id}>{p.name} · {p.sku} · {money(p.selling_price)}</option>)}</select></label>
        <label className="payment-form-label">Quantity<input required type="number" min="0.001" step="0.001" value={form.quantity} onChange={e => setForm({ ...form, quantity: e.target.value })}/></label>
        <label className="payment-form-label">Line discount (KES)<input required type="number" min="0" step="0.01" value={form.discountAmount} onChange={e => setForm({ ...form, discountAmount: e.target.value })}/></label>
      </div>
      {form.productId && <p className="muted">Catalogue price: {money(products.find(p => p.id === form.productId)?.selling_price ?? 0)} · Current product tax rate: {products.find(p => p.id === form.productId)?.tax_rate ?? 0}%. Tax code remains UNMAPPED and requires review before official tax invoicing.</p>}
      <div className="modal-actions"><button type="button" className="provider-cancel" onClick={() => setShowForm(false)}>Cancel</button><button type="submit" className="provider-connect primary" disabled={busy}>{busy ? <><LoaderCircle size={15} className="spin"/> Saving…</> : "Save draft"}</button></div>
    </form>}
    {manualPaymentFor && <form className="product-form" onSubmit={recordManualPayment}>
      <h2>Record payment · {manualPaymentFor.document_number}</h2>
      <p className="muted">Outstanding balance: {money(manualPaymentFor.balance_due)}. M-PESA is confirmed only through the verified STK callback.</p>
      <div className="product-form-grid">
        <label className="payment-form-label">Amount (KES)<input required type="number" min="0.01" max={Number(manualPaymentFor.balance_due)} step="0.01" value={paymentAmount} onChange={e => setPaymentAmount(e.target.value)}/></label>
        <label className="payment-form-label">Tender<select value={paymentTender} onChange={e => setPaymentTender(e.target.value)}><option value="cash">Cash</option><option value="bank_transfer">Bank transfer</option><option value="card">Card (externally confirmed)</option><option value="other">Other</option></select></label>
        <label className="payment-form-label">Reference (optional)<input maxLength={120} value={paymentReference} onChange={e => setPaymentReference(e.target.value)} placeholder="Bank receipt / reference"/></label>
      </div>
      <div className="modal-actions"><button type="button" className="provider-cancel" onClick={() => setManualPaymentFor(null)}>Cancel</button><button type="submit" className="provider-connect primary" disabled={busy}>{busy ? "Saving…" : "Record payment"}</button></div>
    </form>}
    <section className="catalog-table-wrap"><div className="catalog-table-scroll"><table><thead><tr><th>INVOICE</th><th>CREATED</th><th>STATUS</th><th>TOTAL</th><th>PAID</th><th>BALANCE</th><th>ACTION</th></tr></thead><tbody>
      {loading ? <tr><td colSpan={7} className="empty-catalog">Loading invoices…</td></tr> : invoices.length ? invoices.map(invoice => <tr key={invoice.id}>
        <td><span className="catalog-product-name"><span className="catalog-product-icon"><FileText size={16}/></span><strong>{invoice.document_number}</strong></span></td>
        <td>{new Date(invoice.created_at).toLocaleDateString("en-KE")}</td><td><span className={invoice.status === "paid" ? "status completed" : "status pending"}>{invoice.status}</span></td>
        <td className="amount">{money(invoice.grand_total)}</td><td>{money(invoice.amount_paid)}</td><td className="amount">{money(invoice.balance_due)}</td>
        <td>{invoice.status === "draft" ? <button className="provider-connect primary" type="button" disabled={busy} onClick={() => void issue(invoice)}><Send size={14}/> Issue</button> : Number(invoice.balance_due) > 0 && !["void", "credited", "paid"].includes(invoice.status) ? <><button className="provider-connect primary" type="button" disabled={busy} onClick={() => { setManualPaymentFor(invoice); setPaymentAmount(String(invoice.balance_due)); }}>Record payment</button><button className="provider-connect" type="button" disabled={busy} onClick={() => void requestMpesa(invoice)}>M-PESA STK</button></> : <span className="muted">{invoice.status === "paid" ? "Paid" : "eTIMS queued"}</span>}</td>
      </tr>) : <tr><td colSpan={7} className="empty-catalog">No invoices yet. Create a draft to start.</td></tr>}
    </tbody></table></div><div className="table-footer"><span>{invoices.length} invoices</span><span>eTIMS queue status is not proof of KRA acceptance.</span></div></section>
  </>;
}
