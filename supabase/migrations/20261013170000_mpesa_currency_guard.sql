-- Enforce Kenyan-shilling-only M-PESA invoice settlement in the trusted database workflow.
-- This is a new migration because the earlier callback migration has already been applied in production.
create or replace function public.complete_invoice_mpesa_payment(
  p_organization_id uuid,
  p_document_id uuid,
  p_reference text,
  p_checkout_request_id text,
  p_receipt_number text,
  p_amount numeric
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  service_call boolean := coalesce(current_setting('request.jwt.claim.role',true),'')='service_role';
  tx public.provider_transactions%rowtype;
  doc public.sales_documents%rowtype;
  payment_id uuid;
  tender_account uuid;
  ar_account uuid;
  journal_id uuid;
  payment_key text;
begin
  if not service_call then raise exception 'Trusted provider callback required.' using errcode='42501'; end if;
  if p_amount is null or p_amount<=0 or p_amount<>trunc(p_amount)
    or char_length(trim(coalesce(p_receipt_number,'')))<5
    or char_length(trim(coalesce(p_checkout_request_id,'')))<5
    or char_length(trim(coalesce(p_reference,'')))<8 then
    raise exception 'Verified whole-KES provider receipt, checkout and amount are required.' using errcode='22023';
  end if;
  select * into tx from public.provider_transactions
   where organization_id=p_organization_id and document_id=p_document_id and provider='mpesa'
     and reference=p_reference and provider_reference=p_checkout_request_id
   for update;
  if not found then raise exception 'Verified M-PESA invoice transaction not found.' using errcode='23503'; end if;
  if tx.currency_code is distinct from 'KES' then
    raise exception 'M-PESA invoice transactions must be denominated in KES.' using errcode='23514';
  end if;
  payment_key := 'mpesa-invoice:'||tx.reference;
  select id into payment_id from public.document_payments
   where organization_id=p_organization_id and idempotency_key=payment_key;
  if tx.status='succeeded' and payment_id is not null then return payment_id; end if;
  if tx.status<>'pending' then raise exception 'M-PESA invoice transaction is not pending.' using errcode='23514'; end if;
  if round(tx.amount,2)<>round(p_amount,2) then raise exception 'Callback amount does not match the initiated invoice payment.' using errcode='23514'; end if;
  select * into doc from public.sales_documents
   where organization_id=p_organization_id and id=p_document_id for update;
  if not found or doc.document_type<>'invoice' or doc.status in ('draft','void','credited') then
    raise exception 'Invoice is not eligible for payment.' using errcode='23514';
  end if;
  if doc.currency_code is distinct from 'KES' or tx.currency_code is distinct from doc.currency_code then
    raise exception 'M-PESA can only settle KES invoices with a matching transaction currency.' using errcode='23514';
  end if;
  if p_amount>doc.grand_total-doc.amount_paid then raise exception 'Payment exceeds the outstanding invoice balance.' using errcode='23514'; end if;
  select id into tender_account from public.chart_of_accounts
   where organization_id=p_organization_id and system_key='mpesa_clearing' and is_active;
  select id into ar_account from public.chart_of_accounts
   where organization_id=p_organization_id and system_key='accounts_receivable' and is_active;
  if tender_account is null or ar_account is null then raise exception 'Initialize M-PESA clearing and Accounts Receivable accounts first.' using errcode='23514'; end if;
  insert into public.document_payments(organization_id,document_id,tender_type,provider,provider_reference,
    idempotency_key,amount,currency_code,status,received_amount,confirmed_at)
  values(p_organization_id,p_document_id,'mpesa','mpesa',p_receipt_number,payment_key,p_amount,doc.currency_code,'succeeded',p_amount,now())
  returning id into payment_id;
  insert into public.document_payment_allocations(organization_id,document_id,payment_id,amount)
  values(p_organization_id,p_document_id,payment_id,p_amount);
  update public.sales_documents set amount_paid=amount_paid+p_amount,
    status=case when amount_paid+p_amount>=grand_total then 'paid' else 'partially_paid' end,
    updated_at=now()
  where organization_id=p_organization_id and id=p_document_id;
  journal_id := public.post_accounting_journal_internal(
    p_organization_id,(now() at time zone 'Africa/Nairobi')::date,'Verified M-PESA payment for '||doc.document_number,
    'document_payment',payment_id,'receivable_payment',
    jsonb_build_array(
      jsonb_build_object('account_id',tender_account,'debit',p_amount,'credit',0,'description','Verified M-PESA receipt','source_reference',p_receipt_number),
      jsonb_build_object('account_id',ar_account,'debit',0,'credit',p_amount,'description','Clear customer receivable','source_reference',doc.document_number)
    ),null
  );
  insert into public.document_ledger_postings(organization_id,document_id,journal_entry_id,source_type,source_id,posting_purpose,posted_at)
  values(p_organization_id,doc.id,journal_id,'document_payment',payment_id,'receivable_payment',now())
  on conflict (organization_id,source_type,source_id,posting_purpose) do nothing;
  update public.provider_transactions set status='succeeded',updated_at=now()
   where id=tx.id and status='pending';
  return payment_id;
end;
$$;
revoke all on function public.complete_invoice_mpesa_payment(uuid,uuid,text,text,text,numeric) from public,anon,authenticated;
grant execute on function public.complete_invoice_mpesa_payment(uuid,uuid,text,text,text,numeric) to service_role;
