# SafariPOS Release Process

## Branches and approvals

- `main` is intended to be the protected release branch. Do not change the default branch or branch protections until branch histories have been compared and reconciled.
- `foundation/bootstrap` is currently the development/deployment source. Treat it as non-production until deployment mapping is verified.
- Feature work enters through pull requests. Required gates: lint, typecheck, production build, disposable-database migration tests, accounting tests, tenant-isolation tests, and a human approval from the product owner.
- No direct pushes to the release branch after protection is enabled. Tag every approved release as `vMAJOR.MINOR.PATCH` and record its commit SHA, migration range, test run, and rollback notes.

## Environments

- Production and staging must use separate Supabase projects, database URLs, Supabase keys, payment credentials, webhook URLs, eTIMS configuration and Coolify apps.
- Never copy production secrets into staging. Use provider sandbox credentials only in staging.
- Coolify's configured Git repository, branch, deployment commit and health-check URL must be recorded for each environment. A successful GitHub build is not proof that Coolify serves that build.
- The visible SafariPOS footer reads `NEXT_PUBLIC_APP_VERSION`. Set it at build time to the full Git commit SHA (or release tag plus SHA). If it reads `version-unset`, the deployment does not expose a verifiable version.

## Database migration policy: expand, migrate, contract

1. **Expand:** Add backward-compatible nullable columns, tables, indexes and functions. Do not rename/drop existing objects or change meanings required by the previous app.
2. Deploy application code that can work with both the old and expanded schema.
3. Backfill data in a separately monitored, restartable step when required.
4. Switch reads/writes to the new representation only after compatibility tests pass.
5. **Contract:** Remove old columns/functions only in a later release, after the old application version is no longer running and rollback to it is no longer required.
6. Run every migration from an empty disposable database and test upgrade from the currently released schema. Record results before requesting production approval.

## Release procedure

1. Open a PR and run CI, including database migration, tenant isolation, and accounting acceptance tests.
2. Deploy the candidate to staging and apply staging migrations only.
3. Run smoke tests, payment/eTIMS sandbox tests as applicable, and restore drill evidence.
4. Product owner reviews evidence and explicitly approves the production release.
5. Apply the already-tested migration range to production, deploy the matching app version, then run smoke tests. Do not proceed if health checks or schema-version checks fail.
6. Tag the release and attach commit SHA, migration range, CI run, staging test results, deployment verification, and rollback plan.
7. Keep destructive schema changes for a later contract release; do not use a rollback migration to pretend already-posted financial records can safely be erased.

## Backups and restore drills

- Free Supabase projects do not include guaranteed automatic daily backups. Maintain encrypted off-site logical backups and a separate copy of Storage objects; test restoration into staging.
- A database backup does not contain the bytes stored in Supabase Storage. Include Storage objects and required Auth/configuration recovery steps in the disaster-recovery checklist.
- Record backup timestamp, migration/schema version, restore duration, row counts/checksums, and smoke-test result for every drill.
- Never run a restore on production as a test.
