-- Automatically capture an immutable tax snapshot when a sale first becomes completed.
-- This queues data only; it does not submit to KRA or imply protocol certification.
create or replace function public.enqueue_completed_sale_for_etims()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_outbox_id uuid;
  snapshot_payload jsonb;
begin
  if OLD.status is not distinct from 'completed' or NEW.status <> 'completed' then
    return NEW;
  end if;

  snapshot_payload := jsonb_build_object(
    'schema_version', 1,
    'source', 'safaripos.sale_completed',
    'sale', jsonb_build_object(
      'id', NEW.id,
      'organization_id', NEW.organization_id,
      'receipt_number', NEW.receipt_number,
      'currency_code', NEW.currency_code,
      'subtotal', NEW.subtotal,
      'discount_total', NEW.discount_total,
      'tax_total', NEW.tax_total,
      'grand_total', NEW.grand_total,
      'buyer_pin', NEW.buyer_pin,
      'created_at', NEW.created_at,
      'completed_at', clock_timestamp()
    ),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_id', si.product_id,
        'product_name', si.product_name_snapshot,
        'sku', si.sku_snapshot,
        'quantity', si.quantity,
        'unit_price', si.unit_price,
        'discount_amount', si.discount_amount,
        'tax_amount', si.tax_amount,
        'line_total', si.line_total
      ) order by si.id)
      from public.sale_items si
      where si.organization_id = NEW.organization_id and si.sale_id = NEW.id
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'method', sp.method,
        'amount', sp.amount,
        'provider_reference', sp.provider_reference,
        'status', sp.status,
        'created_at', sp.created_at
      ) order by sp.created_at, sp.id)
      from public.sale_payments sp
      where sp.organization_id = NEW.organization_id and sp.sale_id = NEW.id
    ), '[]'::jsonb)
  );

  insert into public.kra_etims_outbox
    (organization_id, source_sale_id, receipt_number, payload_snapshot, status)
  values
    (NEW.organization_id, NEW.id, coalesce(NEW.receipt_number, NEW.id::text), snapshot_payload, 'queued')
  on conflict (organization_id, source_sale_id) do nothing
  returning id into inserted_outbox_id;

  if inserted_outbox_id is not null then
    insert into public.kra_etims_audit_logs
      (organization_id, outbox_id, source_sale_id, event_type, outcome, message, response_metadata)
    values
      (NEW.organization_id, inserted_outbox_id, NEW.id, 'sale_completed_snapshot_created',
       'queued', 'Immutable sale snapshot queued for eTIMS review/submission adapter.',
       jsonb_build_object('schema_version', 1, 'snapshot_item_count',
         jsonb_array_length(coalesce(snapshot_payload->'items', '[]'::jsonb))));
  end if;

  return NEW;
end;
$$;

drop trigger if exists enqueue_completed_sale_for_etims_after_completion on public.sales;
create trigger enqueue_completed_sale_for_etims_after_completion
after update of status on public.sales
for each row
when (new.status = 'completed' and old.status is distinct from 'completed')
execute function public.enqueue_completed_sale_for_etims();

revoke all on function public.enqueue_completed_sale_for_etims() from public, anon, authenticated;
comment on function public.enqueue_completed_sale_for_etims() is
  'Creates one tenant-scoped immutable eTIMS snapshot per completed sale. Queueing only; live KRA submission is disabled until adapter review/certification.';
