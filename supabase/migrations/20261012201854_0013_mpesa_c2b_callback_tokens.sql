alter table public.payment_provider_accounts add column if not exists c2b_callback_token_hash text;
create index if not exists payment_provider_accounts_mpesa_callback_token_idx
 on public.payment_provider_accounts(c2b_callback_token_hash) where provider='mpesa' and c2b_callback_token_hash is not null;
