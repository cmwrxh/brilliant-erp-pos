-- Persist callback authentication and receipt time for idempotent M-PESA STK callback handling.
alter table public.provider_transactions
  add column if not exists callback_token_hash text,
  add column if not exists callback_received_at timestamptz;
create index if not exists provider_transactions_mpesa_checkout_idx
  on public.provider_transactions(provider,provider_reference)
  where provider='mpesa' and provider_reference is not null;
