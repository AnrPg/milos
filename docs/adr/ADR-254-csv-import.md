# ADR-254: Importing clients from a CSV file (Imports context, dry run, idempotent apply, held profiles)
Date: 2026-10-29
Status: Accepted

## Context
Boxes moving to Palee (V3-M10, CP-F3) come with years of clients,
subscription packages, credit, payments and attendance in another system
(Wodify, PushPress, Zen Planner, Arbox) or in a spreadsheet. Re-typing them
is the biggest obstacle to going live. Files differ in encoding (Greek Excel
still saves Windows-1253 or ISO-8859-7), delimiter (`;` in European Excel),
date order (US vendors write month first) and money format (`1.234,56` vs
`1,234.56`). An import must be safe to retry and to repeat with the same
file, must never email anyone by itself, must not reveal whether an email
already has a Palee account (ADR-211), and must be reversible for a while.

## Decision
1. **New context `Palee.Imports`** with three tenant tables, all with forced
   RLS and the `palee_apply_tenant_context` trigger: `imports` (one file:
   source, encoding, delimiter, header, mapping, date order, default role,
   status, preview, summary), `import_rows` (one row of the file: cells,
   fingerprint, outcome, warnings, errors, status, result of applying) and
   `imported_people` (the people an import created or matched, with the
   email and phone key from the file, invitation and removal times).
2. **Pure domain** (`lib/palee/imports/domain/`): encoding detection (BOM,
   UTF-8/16, Windows-1252, ISO-8859-7, Windows-1253), a CSV parser (`,` `;`
   tab, quoted fields, `sep=` hint), dates in a per-import order
   (`dmy`/`mdy`/`ymd`, ISO, Excel serial numbers, EN/EL month names), values
   (emails, phones matched on their last 10 digits, money in EU and US formats
   as integer cents), a fields catalog (20 fields in 5 groups), vendor presets,
   a header matcher, the row plan, the import policy and the tenant data
   policy. Ports `ImportStore` and `Clock`, adapters chosen in config.
3. **Flow.** Upload (multipart, ≤ 5 MB, ≤ 20,000 rows) → mapping (proposed
   from the chosen or best-matching preset; editable while a draft) → **dry
   run** (every row gets an outcome `create_person` / `update_person` /
   `already_imported` / `duplicate_row` / `invalid` and its warnings; nothing
   is written outside the import) → **apply** in an Oban job (inline when Oban
   is off) → report → **invitations**, an explicit step → **undo** within 7
   days of the end.
4. **Idempotency.** Each row's fingerprint is a SHA-256 of its folded values.
   A partial unique index on `(organization_id, fingerprint) WHERE status =
   'applied'` makes "applied once per business" a database fact. Each row is
   applied in its own transaction after locking it and **re-planning against
   current data**, so a retry, a second run or the same file uploaded again
   creates nothing twice (the row becomes `already_imported`). Credit uses a
   request id derived from the fingerprint and is granted once per person.
5. **Matching.** By email among the business's people and earlier imports,
   then by phone key, then rows planned earlier in the same file. An email of
   a Palee account that does **not** belong to the business matches nobody.
   A staff member matched by email is only linked (warning `not_a_client`):
   no finance records.
6. **Writes go through the existing services.** `UpdateFinanceMember`
   (signup source `imported`), `CreateFinancePackage` (once per name) and
   `AssignFinanceMemberPackage`, `Finance.create_manual_credit`,
   `Finance.record_payment` as **history only** (source `import`, never a
   fiscal document), and `Facility` check-ins with a new method `imported`
   (at 12:00 UTC of the date). `Organizations.add_imported_membership` adds a
   client membership without the welcome event.
7. **Held profiles.** A new person becomes a profile with
   `users.held_by_organization_id` set: hidden outside the business like a
   mock person (`palee_demo_user_visible`, notification suppression, people
   search and discovery). Its login gets the real email only when no login
   uses it; otherwise (or without an email) a placeholder
   `held-<uuid>@import.palee.invalid` that never receives mail. The profile is
   released when the person verifies the email or resets the password.
8. **Invitations** are never automatic: `POST …/invitations` sends at most 200
   per call, only to held people with a real address not yet invited,
   through the existing invitation service and its daily limits.
9. **Demo businesses** may upload and dry-run; apply and invitations answer
   `business_not_activated` (`GoLivePolicy` action `:import_people`).
10. **Undo** walks applied rows newest first: deletes the visits, removes the
    payments from the history (soft delete), takes back the credit
    (`Finance.reverse_credit_grant`, a negative reversal entry, never below
    the balance), cancels the subscriptions, closes the finance profiles it
    created and revokes the memberships it added. Packages it created stay.
    Undone rows free their fingerprints. Only a never-applied import can be
    deleted.
11. **Endpoints** under `/api/org/:slug/admin/imports`, capability
    `manage_settings`: `GET /catalog`, `GET /`, `POST /` (multipart, 201),
    `GET /:id`, `GET /:id/rows` (filter `status`, `outcome`, paging
    `after_row`), `POST /:id/preview`, `POST /:id/apply` (202),
    `POST /:id/invitations`, `POST /:id/undo`, `DELETE /:id` (204).

## Rationale
A dry run that runs the same planner as apply makes the preview honest.
Re-planning at apply time (instead of trusting the preview) keeps rows
correct when staff changed data in between or a previous attempt half
finished. A database-enforced fingerprint is the only guard that also holds
for two concurrent runs. Writing through the existing services keeps every
rule (entitlements, audit, ledgers) in one place. Held profiles let staff
see and book imported clients immediately without creating real accounts
for people who never agreed to Palee, and without revealing which emails are
registered.

## Alternatives Considered
- **Matching any Palee account by email.** Rejected: it would join a stranger's
  account to a business on the strength of a spreadsheet and leak account
  existence.
- **Sending invitations on apply.** Rejected: boxes want to check the report
  first and choose when their clients hear from Palee.
- **Importing payments as fiscal documents.** Rejected: they were issued by
  the previous system; reissuing them would double-report to the authority.
- **One transaction for the whole file.** Rejected: one bad row would undo
  20,000, and long transactions block the tenant's tables.

## Consequences
- New tables `imports`, `import_rows`, `imported_people`; `users` gains
  `held_by_organization_id`; check-in method `imported`; Oban queue `imports`.
- The visibility functions that hid mock people now also hide held profiles.
- `Finance` gains `cancel_subscription/3` and `reverse_credit_grant/4`.
- The vendor presets are **best guesses**: Wodify's column names partly come
  from its help page, the others from migration guides of other vendors and
  common names. They only propose a mapping that staff always see and can
  change.
- Follow-up: merging a held profile into a real account that later joins
  with the same email; purging held profiles with their business.

## Implementation Notes
- Migration `20270210000000_create_imports`.
- `save_plans` writes a chunk of plans through `jsonb_to_recordset`.
- Undo runs synchronously; a row that cannot be undone keeps the import
  `applied` and the call answers `undo_incomplete`.
