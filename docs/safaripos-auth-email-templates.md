# SafariPOS Supabase Auth Email Templates

Copy the matching template into **Supabase Dashboard → Authentication → Email Templates**. These are proposed customer-facing copy; verify the correct template variables against the selected Supabase template before saving. Keep the confirmation URL variable intact.

## 1. Confirm signup

**Subject:** Confirm your SafariPOS email

**Body (HTML):**
```html
<h2>Welcome to SafariPOS</h2>
<p>Thanks for creating your SafariPOS account.</p>
<p>Confirm your email address to finish setting up your account.</p>
<p><a href="{{ .ConfirmationURL }}">Confirm email address</a></p>
<p>If you did not create a SafariPOS account, you can ignore this email.</p>
<p>SafariPOS<br>Point of sale and inventory for Kenyan businesses</p>
```

## 2. Password reset

**Subject:** Reset your SafariPOS password

**Body (HTML):**
```html
<h2>Reset your SafariPOS password</h2>
<p>We received a request to reset the password for your SafariPOS account.</p>
<p><a href="{{ .ConfirmationURL }}">Choose a new password</a></p>
<p>If you did not request a password reset, ignore this email. Your password will not change unless you use the link.</p>
<p>For your security, do not forward this email or share the reset link.</p>
<p>SafariPOS<br>Point of sale and inventory for Kenyan businesses</p>
```

## 3. Magic link sign-in

**Subject:** Your SafariPOS sign-in link

**Body (HTML):**
```html
<h2>Sign in to SafariPOS</h2>
<p>Use the secure link below to sign in to your SafariPOS account.</p>
<p><a href="{{ .ConfirmationURL }}">Sign in to SafariPOS</a></p>
<p>If you did not request this link, you can safely ignore this email. Anyone with the link may be able to sign in, so do not forward or share it.</p>
<p>SafariPOS<br>Point of sale and inventory for Kenyan businesses</p>
```

## Before enabling

- Preview and send a test email from Supabase for each template.
- Confirm the redirect URLs point to the intended environment; staging emails must link to staging, not production.
- Do not put passwords, API keys, M-PESA credentials, tax credentials or other secrets in email templates.
- Keep the subject and template variables appropriate for the exact Supabase Auth template type.
