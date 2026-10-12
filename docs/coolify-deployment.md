# Coolify deployment

The application is packaged for a Dockerfile-based Coolify deployment directly from this GitHub repository.

## Coolify service settings

- Repository: `cmwrxh/brilliant-erp-pos`
- Branch: `main` after the pull request is reviewed and merged
- Build pack: Dockerfile
- Dockerfile path: `/Dockerfile`
- Container port: `3000`
- Health check path: `/api/health`
- Persistent volumes: none required for application code; Supabase stores business data
- TLS: enable through Coolify's domain/proxy configuration

## Required runtime environment variables

Set these in Coolify's Environment Variables section. Never add secret values to GitHub.

- `NEXT_PUBLIC_SUPABASE_URL`: URL of the dedicated Brilliant ERP Supabase project.
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`: Supabase publishable key (or legacy anon key).
- `SUPABASE_SERVICE_ROLE_KEY`: server-only service role key; required for encrypted provider credential storage and server-side reconciliation.
- `PAYMENT_CREDENTIALS_ENCRYPTION_KEY`: base64-encoded random 32-byte key. Generate once and preserve it securely; rotating it without re-encrypting existing provider credentials makes them unreadable.
- `APP_BASE_URL`: exact public HTTPS origin, without a trailing slash, used for provider return URLs.

## Before first deployment

1. Confirm all Supabase migrations through `0007_provider_payment_methods` are applied.
2. Add the runtime variables above. Do not deploy payment settings without the service-role key and encryption key.
3. In Supabase Auth, add the production URL and `/onboarding` as allowed redirect URLs.
4. Set the custom domain and HTTPS in Coolify.
5. Deploy the reviewed `main` branch and check `https://YOUR_DOMAIN/api/health`.
6. Create a test user, confirm email, sign in and create a workspace.
7. Add a product, receive stock, and complete a small cash checkout.
8. Configure Flutterwave/Paystack sandbox credentials and verify a full sandbox payment and webhook before considering live activation.

## Important

- M-Pesa and Airtel Money credentials can be saved encrypted, but their country-specific collection and callback integrations are not yet enabled.
- Flutterwave and Paystack are sandbox-only in the application. Live provider credentials remain disabled.
- Do not use the current application for real customer transactions until tenant isolation, provider webhooks, tax treatment, backups and recovery are tested end-to-end.
