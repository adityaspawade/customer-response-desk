# Customer Response Desk

A small-team workspace for customer enquiries, complaints and follow-ups. Built by Aditya Pawade.

[Public demo](https://adiai.si/customer-response-desk.html) · [Portfolio](https://adiai.si)

Version 0.2.0 · MIT licensed · Original app code by Aditya Pawade.

## What works

- Daily queue with overdue, unassigned, owner, category and state filters.
- Manual case intake, enquiry-to-complaint history, escalation, resolution and reopening.
- Editable reply drafts, kept separate from records of messages sent elsewhere.
- Local Excel/CSV reading, sheet/header selection, column mapping and row review.
- Atomic valid-row imports; duplicate references never overwrite existing cases.
- Excel handovers with next actions, UTC deadlines, filters and history.
- Optional private pilot: approved-account sign-in, database persistence, owner-managed access and optimistic concurrency.

The demo resets when reloaded. The private pilot uses a dedicated Supabase database and starts empty. No email replies or scheduled reminders are sent. Files are read locally; valid rows are saved in the private pilot only after the user chooses Import.

## Run the demo

Serve `dist/` with any static web server and open `customer-response-desk.html` (or the directory's index page). No build or model/API key is needed for the demo. Links to Aditya's other portfolio pages belong to the hosted portfolio; the application itself is self-contained in these files.

## Set up your own private pilot

1. Create your own Supabase project. Review its region, plan and usage limits.
2. Apply `docs/sql/customer_response_desk.sql` in that project's SQL editor. The schema is for **one team**, not a public multitenant SaaS.
3. Copy your project API URL and **publishable** key into `dist/assets/desk-config.js`. Never use a secret or service-role key in this browser file.
4. In Supabase Authentication → Users, create the initial pilot user with an email and password chosen by that user. Confirm/auto-confirm the email through the administrator workflow. This creates a separate app login; a Supabase dashboard password is not an app password.
5. Add the first owner's confirmed email to the private access list using an administrator SQL session:

```sql
insert into desk_private.access_list(email,label,role)
values ('owner@example.com','Pilot owner','owner');
```

6. Serve `dist/` over HTTPS and open `customer-response-pilot.html`. Sign in with that pilot account. The owner can grant/revoke access through Team access. Create each teammate's Auth account separately before granting their email access. No invitation email is sent by this app.
7. Test with fictional data: create a case, refresh, sign in in another session, make conflicting edits, export and sign out. Review retention, backups and operational responsibilities before using real customer information.

This sign-in-only pilot does not depend on email redirects or SMTP. Self-registration, email invitations, password-reset email delivery, attachments, automated reminders and mailbox integrations are not included. Administrators handle account recovery through Supabase until those flows are implemented.

## Access model

Confirmed Auth users must match an enabled private access-list entry. JWT user metadata does not grant access. Owners manage team access; agents work on the shared queue. RLS protects every exposed data table; private tables have client privileges revoked. Database triggers preserve earlier history entries, set actor/save metadata and retain revision snapshots. Updates include a previously loaded case version. There is no automatic live refresh and no client delete action.

Limits: 10 MB import file, 2,000 data rows per import, 50 columns, 2,500 pilot cases and 128 KB per case history/document. Date-only deadlines use 23:59 in the viewer's timezone; Excel dates and ISO values without an offset use the viewer's local timezone. Explicit ISO offsets preserve their instant. Exports include UTC deadlines and the display timezone. Keep consistent timezone practices within the team.

## Tests

```sh
node --test tests/desk.test.cjs tests/desk-cloud.test.cjs
```

Or run `npm run check && npm test` with Node 20 or newer. No npm dependency installation is needed. GitHub Actions runs the syntax checks and the 24 app/adapter tests on pushes and pull requests with read-only repository permissions.

`tests/desk-access.sql` verifies the actual database access model, reference uniqueness, stale updates, immutable history and immediate access revocation. It uses fictional Auth/table fixtures in a transaction and rolls back. Run only against a dedicated development/pilot database with administrator access; it expects an otherwise empty case queue.

Automated database/HTTP checks passed for the hosted pilot. Browser sign-in end-to-end and phone rendering have not yet been verified. This is a pilot, not an audited production support system.

## Dependencies and licence

Original app code: MIT, see `LICENSE`.

- SheetJS CE **0.20.3**: Apache 2.0, `dist/assets/vendor/sheetjs-LICENSE.txt`.
- Supabase JS **2.118.0**: MIT, `dist/assets/vendor/supabase-LICENSE.txt`.

The dependencies are vendored at fixed versions. No dependency install/build is required. Supabase charges and limits depend on the project owner's selected plan; a free-plan quote does not imply unlimited service.
