-- Server-side invoice draft and issue lifecycle. Tax codes remain unmapped until KRA policy is approved.
create or replace function public.create_sales_invoice_draft(
  p_organization_id uuid,
  p_document_number text,
  p_customer_id uuid,
  p_location_id uuid,
  p_due_at timestamptz,
  p_lines jsonb,
  p_idempotency_key text
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  existing_id uuid;
  existing_number text;
  existing_customer uuid;
  existing_location uuid;
  document_id uuid;
  line jsonb;
  product_row record;
  line_no integer := 0;
  line_id uuid;
  qty numeric(14,3);
  price numeric(16,4);
  discount numeric(16,2);
  tax_rate numeric(7,4);
  taxable_base numeric(16,2);
  tax_amount numeric(16,2);
  line_total numeric(16,2);
  subtotal_total numeric(16,2) := 0;
  discount_total numeric(16,2) := 0;
  tax_total numeric(16,2) := 0;
  grand_total numeric(16,2) := 0;
begin
  if caller_id is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  select role::text into caller_role from public.organization_members
   where organization_id=p_organization_id and user_id=caller_id;
  if caller_role is null or caller_role not in ('owner','admin','manager') then
    raise exception 'Only an owner, admin or manager can create invoice drafts.' using errcode='42501';
  end if;
  if char_length(trim(coalesce(p_document_number,''))) not between 1 and 80
     or char_length(trim(coalesce(p_idempotency_key,'')))<8
     or p_due_at is null or p_lines is null or jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines)=0 or jsonb_array_length(p_lines)>200 then
    raise exception 'Invoice number, due date, idempotency key and 1–200 lines are required.' using errcode='22023';
  end if;
  if not exists(select 1 from public.customers where organization_id=p_organization_id and id=p_customer_id)
     or not exists(select 1 from public.locations where organization_id=p_organization_id and id=p_location_id and is_active) then
    raise exception 'Choose a customer and active branch in this business.' using errcode='23503';
  end if;
  select id,document_number,customer_id,location_id into existing_id,existing_number,existing_customer,existing_location
   from public.sales_documents where organization_id=p_organization_id and idempotency_key=p_idempotency_key;
  if existing_id is not null then
    if existing_number=trim(p_document_number) and existing_customer=p_customer_id and existing_location=p_location_id then return existing_id; end if;
    raise exception 'Invoice idempotency key was reused for different invoice details.' using errcode='23505';
  end if;
  insert into public.sales_documents(
    organization_id,document_number,document_type,status,customer_id,location_id,due_at,currency_code,
    created_by,idempotency_key
  )
  select p_organization_id,trim(p_document_number),'invoice','draft',p_customer_id,p_location_id,p_due_at,
    o.currency_code,caller_id,p_idempotency_key
  from public.organizations o where o.id=p_organization_id
  returning id into document_id;
  if document_id is null then raise exception 'Business workspace not found.' using errcode='23503'; end if;
  for line in select value from jsonb_array_elements(p_lines) loop
    line_no := line_no+1;
    if coalesce((line->>'quantity')::numeric,0)<=0 or coalesce((line->>'quantity')::numeric,0)>1000000 then
      raise exception 'Invoice quantities must be positive and within supported limits.' using errcode='22023';
    end if;
    select id,name,sku,unit,selling_price,tax_rate,is_active into product_row
    from public.products where organization_id=p_organization_id and id=(line->>'product_id')::uuid;
    if product_row.id is null or not product_row.is_active then
      raise exception 'An invoice product is missing, inactive or belongs to another business.' using errcode='23503';
    end if;
    qty := (line->>'quantity')::numeric;
    price := product_row.selling_price;
    discount := round(coalesce((line->>'discount_amount')::numeric,0),2);
    tax_rate := product_row.tax_rate;
    if discount<0 or discount>round(qty*price,2) then
      raise exception 'Line discount cannot exceed the product line value.' using errcode='22023';
    end if;
    taxable_base := round(qty*price,2)-discount;
    tax_amount := round(taxable_base*tax_rate/100,2);
    line_total := taxable_base+tax_amount;
    insert into public.sales_document_lines(
      organization_id,document_id,line_number,product_id,description_snapshot,sku_snapshot,
      unit_of_measure,quantity,unit_price,discount_amount,tax_code,tax_rate_snapshot,
      taxable_base,tax_amount,line_total
    ) values (
      p_organization_id,document_id,line_no,product_row.id,product_row.name,product_row.sku,
      coalesce(nullif(line->>'unit_of_measure',''),product_row.unit),qty,price,discount,'UNMAPPED',
      tax_rate,taxable_base,tax_amount,line_total
    ) returning id into line_id;
    insert into public.sales_document_tax_lines(
      organization_id,document_id,document_line_id,tax_code_snapshot,tax_rate_snapshot,
      tax_treatment,taxable_base,tax_amount
    ) values (
      p_organization_id,document_id,
      line_id,
      'UNMAPPED',tax_rate,'other',taxable_base,tax_amount
    );
    subtotal_total := subtotal_total+taxable_base;
    discount_total := discount_total+discount;
    tax_total := tax_total+tax_amount;
    grand_total := grand_total+line_total;
  end loop;
  update public.sales_documents set subtotal=subtotal_total,discount_total=discount_total,
    tax_total=tax_total,grand_total=grand_total,updated_at=now()
  where organization_id=p_organization_id and id=document_id;
  return document_id;
end;
$$;
revoke all on function public.create_sales_invoice_draft(uuid,text,uuid,uuid,timestamptz,jsonb,text) from public,anon;
grant execute on function public.create_sales_invoice_draft(uuid,text,uuid,uuid,timestamptz,jsonb,text) to authenticated;

create or replace function public.issue_sales_invoice(
  p_organization_id uuid,
  p_document_id uuid
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  doc public.sales_documents%rowtype;
  ar_account uuid;
  revenue_account uuid;
  vat_account uuid;
  journal_lines jsonb := '[]'::jsonb;
  journal_id uuid;
  submission_key text;
  fingerprint text;
begin
  if caller_id is null then raise exception 'Authentication required.' using errcode='28000'; end if;
  select role::text into caller_role from public.organization_members
   where organization_id=p_organization_id and user_id=caller_id;
  if caller_role is null or caller_role not in ('owner','admin','manager') then
    raise exception 'Only an owner, admin or manager can issue invoices.' using errcode='42501';
  end if;
  select * into doc from public.sales_documents
   where organization_id=p_organization_id and id=p_document_id for update;
  if not found or doc.document_type<>'invoice' then
    raise exception 'Invoice not found for this business.' using errcode='23503';
  end if;
  if doc.status in ('issued','sent','partially_paid','paid','overdue') then return doc.id; end if;
  if doc.status<>'draft' or doc.grand_total<=0
     or not exists(select 1 from public.sales_document_lines where organization_id=p_organization_id and document_id=doc.id) then
    raise exception 'Only a non-empty invoice draft with a positive total can be issued.' using errcode='23514';
  end if;
  select id into ar_account from public.chart_of_accounts where organization_id=p_organization_id and system_key='accounts_receivable' and is_active;
  select coa.id into revenue_account
    from public.chart_of_accounts coa
    join public.organizations o on o.id=coa.organization_id
    where coa.organization_id=p_organization_id and coa.is_active
      and coa.system_key=case o.business_model
        when 'wholesale' then 'wholesale_sales'
        when 'services' then 'other_income'
        else 'retail_sales'
      end;
  select id into vat_account from public.chart_of_accounts where organization_id=p_organization_id and system_key='vat_output' and is_active;
  if ar_account is null or revenue_account is null or (doc.tax_total>0 and vat_account is null) then
    raise exception 'Initialize Accounts Receivable, sales revenue and output VAT accounts first.' using errcode='23514';
  end if;
  journal_lines := journal_lines || jsonb_build_array(jsonb_build_object(
    'account_id',ar_account,'debit',doc.grand_total,'credit',0,'description','Customer receivable','source_reference',doc.document_number
  ));
  journal_lines := journal_lines || jsonb_build_array(jsonb_build_object(
    'account_id',revenue_account,'debit',0,'credit',doc.subtotal,'description','Invoice revenue','source_reference',doc.document_number
  ));
  if doc.tax_total>0 then
    journal_lines := journal_lines || jsonb_build_array(jsonb_build_object(
      'account_id',vat_account,'debit',0,'credit',doc.tax_total,'description','Output VAT (tax code mapping pending)','source_reference',doc.document_number
    ));
  end if;
  journal_id := public.post_accounting_journal_internal(
    p_organization_id,(now() at time zone 'Africa/Nairobi')::date,
    'Issue invoice '||doc.document_number,'sales_invoice',doc.id,'invoice_issue',journal_lines,null
  );
  update public.sales_documents set status='issued',issued_at=now(),updated_at=now()
   where organization_id=p_organization_id and id=doc.id;
  insert into public.document_ledger_postings(organization_id,document_id,journal_entry_id,source_type,source_id,posting_purpose,posted_at)
  values(p_organization_id,doc.id,journal_id,'sales_invoice',doc.id,'invoice_issue',now())
  on conflict (organization_id,source_type,source_id,posting_purpose) do nothing;
  submission_key := 'etims-invoice-'||doc.id::text;
  fingerprint := encode(extensions.digest(convert_to(doc.id::text||':'||doc.document_number||':'||doc.grand_total::text,'UTF8'),'sha256'),'hex');
  insert into public.document_etims_submissions(organization_id,document_id,submission_mode,idempotency_key,request_fingerprint,status)
  values(p_organization_id,doc.id,'other',submission_key,fingerprint,'queued')
  on conflict (organization_id,idempotency_key) do nothing;
  return doc.id;
end;
$$;
revoke all on function public.issue_sales_invoice(uuid,uuid) from public,anon;
grant execute on function public.issue_sales_invoice(uuid,uuid) to authenticated;
