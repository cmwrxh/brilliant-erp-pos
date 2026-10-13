# Coolify deployment

The application is packaged for a Dockerfile-based Coolify deployment directly from this GitHub repository.

## Coolify service settings

- Repository: `cmwrxh/brilliant-erp-pos`
- Release branch: `main` after the reviewed pull request is merged
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

## Before first deployment or database release

1. Confirm the intended Supabase project is the dedicated `Brilliant-ERP-POS` project and is healthy.
2. Compare repository migration versions with the remote Supabase migration history. The source filenames use the recorded remote versions through `20261013180900_secure_accounting_journal_reversal`. Apply only migrations confirmed to be pending. Never blindly replay historical migrations or run a production `db push` when version histories disagree.
3. Add the runtime variables above. Do not enable payment workflows without the service-role key and encryption key.
4. In Supabase Auth, add the production URL and `/onboarding` as allowed redirect URLs. Enable leaked-password protection in the Auth security settings.
5. Set the custom domain and HTTPS in Coolify.
6. Deploy the reviewed `main` branch and check `https://YOUR_DOMAIN/api/health`.
7. Create a dedicated test user, confirm email, sign in and create a workspace.
8. Add a test product, receive stock with a unit cost, and complete a small cash checkout. Verify stock, receipt, and accounting entries before repeating with another tenant.
9. Configure provider sandbox credentials and verify the full hosted-payment, callback, duplicate-callback, and failed-payment flows before considering live activation.

## Integration and release boundaries

- Flutterwave and Paystack code paths are intended for sandbox validation; do not enable live credentials until end-to-end verification is documented.
- M-PESA STK and C2B callback routes exist, but public-HTTPS sandbox tests, Daraja callback registration, duplicate-event checks, and reconciliation acceptance remain outstanding. Do not use live M-PESA credentials yet.
- Airtel Money collection is not implemented; storing provider configuration is not a working payment integration.
- KRA eTIMS is not production-ready until taxpayer onboarding, tax mapping, OSCU/VSCU sandbox tests, and KRA certification/approval are complete.
- Offline-first checkout is not implemented in the POS UI. Do not promise offline sales.
- Keep invoice and accounting workflow release flags disabled until tax mapping, end-to-end tests, and professional accounting acceptance are complete.
- A successful GitHub build or `/api/health` response alone does not prove authentication, tenant isolation, checkout, accounting, or provider integrations work end to end.
