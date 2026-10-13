-- Narrow server-side workflows for supplier master data, supplier bills and AP payments.
create unique index supplier_bills_source_fingerprint_uq
  on public.supplier_bills(organization_id,source_fingerprint)
  where source_fingerprint is not null;

create or replace function public.create_supplier(
  p_organization_id uuid,
  p_name text,
  p_supplier_code text default null,
  p_kra_pin text default null,
  p_phone text default null,
  p_email text default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  supplier_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  select role::text into caller_role from public.organization_members
    where organization_id=p_organization_id and user_id=caller_id;
  if caller_role is null or caller_role not in ('owner','admin','manager') then
    raise exception 'Not authorized to manage suppliers.' using errcode='42501';
  end if;
  if char_length(trim(coalesce(p_name,''))) not between 2 and 200 then
    raise exception 'Supplier name must be between 2 and 200 characters.' using errcode='22023';
  end if;
  insert into public.suppliers(organization_id,name,supplier_code,kra_pin,phone,email)
  values(p_organization_id,trim(p_name),nullif(trim(p_supplier_code),''),nullif(trim(p_kra_pin),''),nullif(trim(p_phone),''),nullif(trim(p_email),''))
  returning id into supplier_id;
  return supplier_id;
end;
$$;
revoke all on function public.create_supplier(uuid,text,text,text,text,text) from public,anon;
grant execute on function public.create_supplier(uuid,text,text,text,text,text) to authenticated;

create or replace function public.create_supplier_bill(
  p_organization_id uuid,
  p_supplier_id uuid,
  p_supplier_invoice_number text,
  p_bill_date date,
  p_due_date date,
  p_lines jsonb,
  p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  existing_id uuid;
  existing_supplier_id uuid;
  existing_invoice_number text;
  bill_id uuid;
  ap_account uuid;
  input_vat_account uuid;
  journal_id uuid;
  line jsonb;
  journal_lines jsonb := '[]'::jsonb;
  net_total numeric(16,2) := 0;
  tax_total numeric(16,2) := 0;
  line_no integer := 0;
  account_row record;
begin
  if caller_id is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  select role::text into caller_role from public.organization_members
    where organization_id=p_organization_id and user_id=caller_id;
  if caller_role is null or caller_role not in ('owner','admin','manager') then
    raise exception 'Not authorized to post supplier bills.' using errcode='42501';
  end if;
  if p_bill_date is null or p_due_date is not null and p_due_date<p_bill_date
    or char_length(trim(coalesce(p_supplier_invoice_number,''))) not between 1 and 100
    or char_length(trim(coalesce(p_idempotency_key,'')))<8
    or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'Supplier invoice number, dates, idempotency key and at least one bill line are required.' using errcode='22023';
  end if;
  if not exists(select 1 from public.suppliers where organization_id=p_organization_id and id=p_supplier_id and is_active) then
    raise exception 'Supplier is missing, inactive or belongs to another business.' using errcode='23503';
  end if;
  select id,supplier_id,supplier_invoice_number into existing_id,existing_supplier_id,existing_invoice_number
   from public.supplier_bills where organization_id=p_organization_id and source_fingerprint=p_idempotency_key;
  if existing_id is not null then
    if existing_supplier_id=p_supplier_id and existing_invoice_number=trim(p_supplier_invoice_number) then return existing_id; end if;
    raise exception 'Supplier bill idempotency key was reused for different bill details.' using errcode='23505';
  end if;
  select id into existing_id from public.supplier_bills
   where organization_id=p_organization_id and supplier_id=p_supplier_id and supplier_invoice_number=trim(p_supplier_invoice_number);
  if existing_id is not null then
    raise exception 'This supplier invoice number already exists; review the existing bill instead of duplicating it.' using errcode='23505';
  end if;
  select id into ap_account from public.chart_of_accounts
   where organization_id=p_organization_id and system_key='accounts_payable' and is_active;
  select id into input_vat_account from public.chart_of_accounts
   where organization_id=p_organization_id and system_key='vat_input' and is_active;
  if ap_account is null then raise exception 'Initialize the Accounts Payable control account first.' using errcode='23514'; end if;
  for line in select value from jsonb_array_elements(p_lines) loop
    line_no := line_no+1;
    if char_length(trim(coalesce(line->>'description',''))) not between 2 and 500
      or coalesce((line->>'net_amount')::numeric,-1)<0
      or coalesce((line->>'tax_amount')::numeric,0)<0
      or coalesce((line->>'net_amount')::numeric,0)+coalesce((line->>'tax_amount')::numeric,0)<=0 then
      raise exception 'Each supplier bill line needs a description and a positive net or tax amount.' using errcode='22023';
    end if;
    select id,account_type,is_control,system_key into account_row
      from public.chart_of_accounts where organization_id=p_organization_id
       and code=line->>'account_code' and is_active;
    if account_row.id is null or (account_row.account_type not in ('asset','expense'))
       or (account_row.is_control and account_row.system_key<>'inventory') then
      raise exception 'Supplier bill line account must be an active asset/expense account; only inventory control is allowed among control accounts.' using errcode='23514';
    end if;
    net_total := net_total+round((line->>'net_amount')::numeric,2);
    tax_total := tax_total+round(coalesce((line->>'tax_amount')::numeric,0),2);
    journal_lines := journal_lines || jsonb_build_array(jsonb_build_object(
      'account_id',account_row.id,'debit',round((line->>'net_amount')::numeric,2),'credit',0,
      'description',left(line->>'description',500),'source_reference',p_supplier_invoice_number
    ));
  end loop;
  if net_total+tax_total<=0 then raise exception 'Supplier bill total must be positive.' using errcode='22023'; end if;
  if tax_total>0 then
    if input_vat_account is null then raise exception 'Input VAT control account is missing.' using errcode='23514'; end if;
    journal_lines := journal_lines || jsonb_build_array(jsonb_build_object(
      'account_id',input_vat_account,'debit',tax_total,'credit',0,
      'description','Recoverable input VAT','source_reference',p_supplier_invoice_number
    ));
  end if;
  journal_lines := journal_lines || jsonb_build_array(jsonb_build_object(
    'account_id',ap_account,'debit',0,'credit',net_total+tax_total,
    'description','Supplier payable','source_reference',p_supplier_invoice_number
  ));
  insert into public.supplier_bills(organization_id,supplier_id,supplier_invoice_number,bill_date,due_date,subtotal,input_tax,source_fingerprint,created_by)
  values(p_organization_id,p_supplier_id,trim(p_supplier_invoice_number),p_bill_date,p_due_date,net_total,tax_total,p_idempotency_key,caller_id)
  returning id into bill_id;
  line_no := 0;
  for line in select value from jsonb_array_elements(p_lines) loop
    line_no := line_no+1;
    insert into public.supplier_bill_lines(organization_id,bill_id,line_number,description,account_code,net_amount,tax_amount)
    values(p_organization_id,bill_id,line_no,left(trim(line->>'description'),500),trim(line->>'account_code'),
      round((line->>'net_amount')::numeric,2),round(coalesce((line->>'tax_amount')::numeric,0),2));
  end loop;
  journal_id := public.post_accounting_journal_internal(
    p_organization_id,p_bill_date,'Supplier bill '||trim(p_supplier_invoice_number),
    'supplier_bill',bill_id,'supplier_bill',journal_lines,null
  );
  return bill_id;
end;
$$;
revoke all on function public.create_supplier_bill(uuid,uuid,text,date,date,jsonb,text) from public,anon;
grant execute on function public.create_supplier_bill(uuid,uuid,text,date,date,jsonb,text) to authenticated;

create or replace function public.record_supplier_bill_payment(
  p_organization_id uuid,
  p_bill_id uuid,
  p_tender_type text,
  p_amount numeric,
  p_idempotency_key text,
  p_provider_reference text default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  bill public.supplier_bills%rowtype;
  payment_id uuid;
  existing_bill_id uuid;
  existing_amount numeric(16,2);
  existing_tender text;
  existing_reference text;
  ap_account uuid;
  tender_account uuid;
  tender_key text;
  journal_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  select role::text into caller_role from public.organization_members
    where organization_id=p_organization_id and user_id=caller_id;
  if caller_role is null or caller_role not in ('owner','admin','manager') then
    raise exception 'Not authorized to pay supplier bills.' using errcode='42501';
  end if;
  if p_tender_type not in ('cash','mpesa','bank_transfer','other')
     or p_amount is null or p_amount<=0 or char_length(trim(coalesce(p_idempotency_key,'')))<8 then
    raise exception 'Valid tender, amount and idempotency key are required.' using errcode='22023';
  end if;
  if p_tender_type='mpesa' and char_length(trim(coalesce(p_provider_reference,'')))<4 then
    raise exception 'M-PESA payment reference is required.' using errcode='22023';
  end if;
  select * into bill from public.supplier_bills
   where organization_id=p_organization_id and id=p_bill_id for update;
  if not found or bill.status='void' then raise exception 'Supplier bill is missing or void.' using errcode='23514'; end if;
  select id,bill_id,amount,tender_type,provider_reference into payment_id,existing_bill_id,existing_amount,existing_tender,existing_reference
   from public.supplier_bill_payments where organization_id=p_organization_id and idempotency_key=p_idempotency_key;
  if payment_id is not null then
    if existing_bill_id=p_bill_id and existing_amount=p_amount and existing_tender=p_tender_type
       and existing_reference is not distinct from p_provider_reference then return payment_id; end if;
    raise exception 'Idempotency key was already used for a different supplier payment.' using errcode='23505';
  end if;
  if p_amount>bill.total_amount-bill.amount_paid then raise exception 'Payment exceeds supplier bill balance.' using errcode='23514'; end if;
  select id into ap_account from public.chart_of_accounts where organization_id=p_organization_id and system_key='accounts_payable' and is_active;
  tender_key := case p_tender_type when 'cash' then 'cash' when 'mpesa' then 'mpesa_clearing' when 'bank_transfer' then 'bank' else 'cash' end;
  select id into tender_account from public.chart_of_accounts where organization_id=p_organization_id and system_key=tender_key and is_active;
  if ap_account is null or tender_account is null then raise exception 'Required Accounts Payable and tender accounts are missing.' using errcode='23514'; end if;
  insert into public.supplier_bill_payments(organization_id,bill_id,tender_type,provider_reference,idempotency_key,amount,created_by)
  values(p_organization_id,p_bill_id,p_tender_type,p_provider_reference,p_idempotency_key,p_amount,caller_id)
  returning id into payment_id;
  update public.supplier_bills set amount_paid=amount_paid+p_amount,
    status=case when amount_paid+p_amount>=total_amount then 'paid' else 'partially_paid' end,updated_at=now()
  where organization_id=p_organization_id and id=p_bill_id;
  journal_id := public.post_accounting_journal_internal(
    p_organization_id,current_date,'Payment for supplier bill '||bill.supplier_invoice_number,
    'supplier_bill_payment',payment_id,'supplier_payment',
    jsonb_build_array(
      jsonb_build_object('account_id',ap_account,'debit',p_amount,'credit',0,'description','Clear supplier payable','source_reference',bill.supplier_invoice_number),
      jsonb_build_object('account_id',tender_account,'debit',0,'credit',p_amount,'description','Supplier payment','source_reference',coalesce(p_provider_reference,p_idempotency_key))
    ),null
  );
  return payment_id;
end;
$$;
revoke all on function public.record_supplier_bill_payment(uuid,uuid,text,numeric,text,text) from public,anon;
grant execute on function public.record_supplier_bill_payment(uuid,uuid,text,numeric,text,text) to authenticated;
