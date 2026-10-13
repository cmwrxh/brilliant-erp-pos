-- Database-level release gates. Environment flags alone are not a security boundary because
-- authenticated clients can call granted RPCs directly through PostgREST.
alter table public.accounting_settings
  add column invoice_workflows_enabled boolean not null default false,
  add column accounting_workflows_enabled boolean not null default false;

create or replace function public.enforce_safaripos_workflow_gate()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  org_id uuid;
  doc_id uuid;
  doc_type text;
  invoice_enabled boolean := false;
  accounting_enabled boolean := false;
begin
  org_id := case when TG_OP='DELETE' then OLD.organization_id else NEW.organization_id end;
  if TG_TABLE_NAME='sales_documents' then
    doc_type := case when TG_OP='DELETE' then OLD.document_type else NEW.document_type end;
    if doc_type not in ('invoice','credit_note') then
      if TG_OP='DELETE' then return OLD; else return NEW; end if;
    end if;
    select invoice_workflows_enabled into invoice_enabled
      from public.accounting_settings where organization_id=org_id;
    if not coalesce(invoice_enabled,false) then
      raise exception 'Invoice workflows are disabled until migration, tax mapping, eTIMS sandbox and accounting acceptance gates pass.' using errcode='55000';
    end if;
    if TG_OP='DELETE' then return OLD; else return NEW; end if;
  end if;

  if TG_TABLE_NAME in ('sales_document_lines','sales_document_tax_lines','document_payments',
      'document_payment_allocations','document_ledger_postings','document_etims_submissions') then
    doc_id := case when TG_OP='DELETE' then OLD.document_id else NEW.document_id end;
    select document_type into doc_type from public.sales_documents
      where organization_id=org_id and id=doc_id;
    if doc_type in ('invoice','credit_note') then
      select invoice_workflows_enabled into invoice_enabled
        from public.accounting_settings where organization_id=org_id;
      if not coalesce(invoice_enabled,false) then
        raise exception 'Invoice workflows are disabled until release acceptance gates pass.' using errcode='55000';
      end if;
    end if;
    if TG_OP='DELETE' then return OLD; else return NEW; end if;
  end if;

  if TG_TABLE_NAME='provider_transactions' then
    doc_id := case when TG_OP='DELETE' then OLD.document_id else NEW.document_id end;
    if doc_id is null then
      if TG_OP='DELETE' then return OLD; else return NEW; end if;
    end if;
    select invoice_workflows_enabled into invoice_enabled
      from public.accounting_settings where organization_id=org_id;
    if not coalesce(invoice_enabled,false) then
      raise exception 'Invoice payment initiation is disabled until release acceptance gates pass.' using errcode='55000';
    end if;
    if TG_OP='DELETE' then return OLD; else return NEW; end if;
  end if;

  if TG_TABLE_NAME in ('suppliers','supplier_bills','supplier_bill_lines','supplier_bill_payments',
      'mpesa_settlements','mpesa_settlement_matches') then
    select accounting_workflows_enabled into accounting_enabled
      from public.accounting_settings where organization_id=org_id;
    if not coalesce(accounting_enabled,false) then
      raise exception 'Supplier and settlement workflows are disabled until accounting acceptance gates pass.' using errcode='55000';
    end if;
  end if;
  if TG_OP='DELETE' then return OLD; else return NEW; end if;
end;
$$;
revoke all on function public.enforce_safaripos_workflow_gate() from public,anon,authenticated;

create trigger gate_sales_documents before insert or update or delete on public.sales_documents
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_sales_document_lines before insert or update or delete on public.sales_document_lines
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_sales_document_tax_lines before insert or update or delete on public.sales_document_tax_lines
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_document_payments before insert or update or delete on public.document_payments
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_document_payment_allocations before insert or update or delete on public.document_payment_allocations
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_document_ledger_postings before insert or update or delete on public.document_ledger_postings
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_document_etims_submissions before insert or update or delete on public.document_etims_submissions
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_provider_transactions_invoice before insert or update or delete on public.provider_transactions
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_suppliers before insert or update or delete on public.suppliers
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_supplier_bills before insert or update or delete on public.supplier_bills
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_supplier_bill_lines before insert or update or delete on public.supplier_bill_lines
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_supplier_bill_payments before insert or update or delete on public.supplier_bill_payments
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_mpesa_settlements before insert or update or delete on public.mpesa_settlements
  for each row execute function public.enforce_safaripos_workflow_gate();
create trigger gate_mpesa_settlement_matches before insert or update or delete on public.mpesa_settlement_matches
  for each row execute function public.enforce_safaripos_workflow_gate();

comment on column public.accounting_settings.invoice_workflows_enabled is
  'Disabled by default; enable only via a reviewed migration after tax mapping, eTIMS sandbox and accounting acceptance.';
comment on column public.accounting_settings.accounting_workflows_enabled is
  'Disabled by default; enable only via a reviewed migration after supplier/AP and settlement accounting acceptance.';
