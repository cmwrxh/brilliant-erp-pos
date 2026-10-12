# Security policy

## Current status
This repository is an early development foundation. Do not use it to process real customer, inventory, tax, or payment data until authentication, authorization, transactional workflows, monitoring, backups, and tests have been reviewed.

## Secrets
- Never commit environment files, access tokens, database passwords, service-role keys, M-Pesa credentials, or production exports.
- Use the example environment file as a list of variable names only.
- Configure secrets in Coolify or the appropriate secret manager.
- Rotate any credential accidentally committed and remove it from active use; deleting a file in a later commit is not sufficient.

## Tenant boundaries
- Enforce authorization in PostgreSQL RLS and trusted server-side code.
- Every query and mutation must be scoped to an authenticated organization membership.
- Test that one tenant cannot read, modify, infer, or reference another tenant's data.
- Do not expose service-role credentials to client-side bundles.

## Reporting a vulnerability
Please report suspected security issues privately to the repository maintainer. Do not publish exploit details or customer data in public issues.
