"use client";

import { useCallback, useEffect, useState } from "react";
import { Edit2, Plus, Search, Package, LoaderCircle } from "lucide-react";

type Product = {
  id: string;
  sku: string;
  name: string;
  barcode: string | null;
  unit: string;
  cost_price: number | string;
  selling_price: number | string;
  tax_rate: number | string;
  is_active: boolean;
};

type ProductForm = {
  sku: string;
  name: string;
  barcode: string;
  unit: string;
  costPrice: string;
  sellingPrice: string;
  taxRate: string;
  isActive: boolean;
};

const emptyForm: ProductForm = {
  sku: "",
  name: "",
  barcode: "",
  unit: "each",
  costPrice: "0",
  sellingPrice: "0",
  taxRate: "0",
  isActive: true,
};

function toForm(product: Product): ProductForm {
  return {
    sku: product.sku,
    name: product.name,
    barcode: product.barcode ?? "",
    unit: product.unit,
    costPrice: String(product.cost_price),
    sellingPrice: String(product.selling_price),
    taxRate: String(product.tax_rate),
    isActive: product.is_active,
  };
}

export function ProductManager({ organizationId }: { organizationId: string }) {
  const [products, setProducts] = useState<Product[]>([]);
  const [search, setSearch] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [showForm, setShowForm] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);
  const [form, setForm] = useState<ProductForm>(emptyForm);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch(
        "/api/products?organizationId=" + encodeURIComponent(organizationId),
        { cache: "no-store" },
      );
      const data = await response.json();
      if (!response.ok) throw new Error(data.error ?? "Could not load products.");
      setProducts(data.products ?? []);
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load products.");
    } finally {
      setLoading(false);
    }
  }, [organizationId]);

  useEffect(() => {
    void load();
  }, [load]);

  function openCreateForm() {
    setEditingProduct(null);
    setForm(emptyForm);
    setError("");
    setShowForm(true);
  }

  function openEditForm(product: Product) {
    setEditingProduct(product);
    setForm(toForm(product));
    setError("");
    setShowForm(true);
  }

  async function save(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const payload = {
        ...form,
        organizationId,
        costPrice: Number(form.costPrice),
        sellingPrice: Number(form.sellingPrice),
        taxRate: Number(form.taxRate),
      };
      const response = await fetch("/api/products", {
        method: editingProduct ? "PATCH" : "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(editingProduct ? { ...payload, id: editingProduct.id } : payload),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error ?? "Could not save product.");

      if (editingProduct) {
        setProducts((previous) =>
          previous.map((product) => product.id === data.product.id ? data.product : product)
            .sort((a, b) => a.name.localeCompare(b.name)),
        );
      } else {
        setProducts((previous) =>
          [...previous, data.product].sort((a, b) => a.name.localeCompare(b.name)),
        );
      }
      setShowForm(false);
      setEditingProduct(null);
      setForm(emptyForm);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not save product.");
    } finally {
      setBusy(false);
    }
  }

  const filtered = products.filter((product) =>
    (product.name + " " + product.sku + " " + (product.barcode ?? ""))
      .toLowerCase()
      .includes(search.toLowerCase()),
  );

  return (
    <>
      <div className="catalog-toolbar">
        <div className="catalog-search">
          <Search size={16} />
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search by product, SKU or barcode"
            aria-label="Search products"
          />
        </div>
        <button className="primary-button" onClick={openCreateForm} type="button">
          <Plus size={16} /> Add product
        </button>
      </div>

      {error && <p className="form-feedback error-feedback" role="alert">{error}</p>}

      {showForm && (
        <form className="product-form" onSubmit={save}>
          <h2>{editingProduct ? "Edit product" : "New product"}</h2>
          <div className="product-form-grid">
            <label className="payment-form-label">
              Product name
              <input required minLength={2} maxLength={160} value={form.name}
                onChange={(event) => setForm({ ...form, name: event.target.value })} />
            </label>
            <label className="payment-form-label">
              SKU
              <input required maxLength={80} value={form.sku}
                onChange={(event) => setForm({ ...form, sku: event.target.value })} />
            </label>
            <label className="payment-form-label">
              Barcode (optional)
              <input value={form.barcode}
                onChange={(event) => setForm({ ...form, barcode: event.target.value })} />
            </label>
            <label className="payment-form-label">
              Unit
              <input required maxLength={30} value={form.unit}
                onChange={(event) => setForm({ ...form, unit: event.target.value })}
                placeholder="each, kg, litre" />
            </label>
            <label className="payment-form-label">
              Cost price (KES)
              <input type="number" min="0" step=".01" required value={form.costPrice}
                onChange={(event) => setForm({ ...form, costPrice: event.target.value })} />
            </label>
            <label className="payment-form-label">
              Selling price (KES)
              <input type="number" min="0" step=".01" required value={form.sellingPrice}
                onChange={(event) => setForm({ ...form, sellingPrice: event.target.value })} />
            </label>
            <label className="payment-form-label">
              Tax rate (%)
              <input type="number" min="0" max="100" step=".001" required value={form.taxRate}
                onChange={(event) => setForm({ ...form, taxRate: event.target.value })} />
            </label>
            <label className="payment-form-label">
              Status
              <select value={form.isActive ? "active" : "inactive"}
                onChange={(event) => setForm({ ...form, isActive: event.target.value === "active" })}>
                <option value="active">Active</option>
                <option value="inactive">Inactive</option>
              </select>
            </label>
          </div>
          <div className="modal-actions">
            <button className="provider-cancel" type="button" onClick={() => {
              setShowForm(false);
              setEditingProduct(null);
              setError("");
            }}>Cancel</button>
            <button className="provider-connect primary" type="submit" disabled={busy}>
              {busy ? <><LoaderCircle size={15} className="spin" /> Saving…</> : editingProduct ? "Save changes" : "Save product"}
            </button>
          </div>
        </form>
      )}

      <section className="catalog-table-wrap">
        <div className="catalog-table-scroll">
          <table>
            <thead>
              <tr>
                <th>PRODUCT</th>
                <th>SKU / BARCODE</th>
                <th>COST</th>
                <th>SELLING PRICE</th>
                <th>TAX</th>
                <th>STATUS</th>
                <th>ACTIONS</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={7} className="empty-catalog">Loading products…</td></tr>
              ) : filtered.length ? filtered.map((product) => (
                <tr key={product.id}>
                  <td><span className="catalog-product-name"><span className="catalog-product-icon"><Package size={16} /></span><strong>{product.name}</strong></span></td>
                  <td><strong>{product.sku}</strong><small className="catalog-subline">{product.barcode ?? "No barcode"}</small></td>
                  <td>KES {Number(product.cost_price).toLocaleString("en-KE", { minimumFractionDigits: 2 })}</td>
                  <td className="amount">KES {Number(product.selling_price).toLocaleString("en-KE", { minimumFractionDigits: 2 })}</td>
                  <td>{Number(product.tax_rate)}%</td>
                  <td><span className={product.is_active ? "status completed" : "status pending"}>{product.is_active ? "Active" : "Inactive"}</span></td>
                  <td><button className="provider-cancel" type="button" onClick={() => openEditForm(product)} aria-label={"Edit " + product.name}><Edit2 size={14} /> Edit</button></td>
                </tr>
              )) : (
                <tr><td colSpan={7} className="empty-catalog">{search ? "No products match your search." : "No products yet. Add your first product to get started."}</td></tr>
              )}
            </tbody>
          </table>
        </div>
        <div className="table-footer"><span>{filtered.length} products</span><span>Currency: KES · Tax rates are configurable per product</span></div>
      </section>
    </>
  );
}
