# Validation

Run `npm run check && npm test` from the repository root. The 24 app and adapter tests need Node 20 or newer and no dependency install.

`desk-access.sql` is a separate database integration check for a dedicated empty development database. It creates fictional test fixtures inside a transaction and rolls back; it needs database administrator access and is not run by GitHub Actions.
