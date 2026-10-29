# ADR-267: Privacy policy and terms pages, minimum age 16 at sign-up, "Download my data"
Date: 2026-10-29
Status: Accepted

## Context
The store-release gap analysis (V3-M12, `v3-store-release-prep.md` §3.2 and
§3.9) found four things missing before the apps can be submitted:

1. No privacy policy (GDPR articles 13 and 14) or terms of use page. The
   stores require a privacy policy URL, and Health Connect's «why does this
   app need access» link opened `/me/devices` instead of a policy.
2. Sign-up asked nothing about age. The terms will set a minimum age and the
   store questionnaires ask for one.
3. A person could export only parts of their data (journal, wellness,
   devices), never everything in one request (articles 15 and 20).
4. Nothing recorded these choices.

## Decision

### 1. `/privacy` and `/terms`
- Two public, server-rendered pages in the web app, in all 12 locales from
  the `legal` message namespace, clearly marked **draft for review by
  Palee's law consultant**. The controller, its address, the contact and
  the hosting provider are visible placeholders (`[…]`) until filled in.
- The privacy page lists only what the code really does: the data
  categories of `apps/mobile/config/data-collection.json`, the
  sub-processors found in the code (Brevo, Google Gemini, Anthropic, Apple
  APNs, Google FCM, Cloudflare, komoot Photon, OpenFreeMap, Stripe, Viva,
  fiskaly, AADE myDATA, Garmin as a separate controller, hosting provider
  placeholder), retention (account deletion after 7 days, ADR-211;
  business records kept by law, ADR-117/ADR-246; a box's data — signed
  documents and their certificates included — kept 5 years after the box
  is deleted) and the rights with the way to use each one in the app.
- The sub-processor list is data (`lib/legal/sub-processors.ts`): names and
  hosts stay as they are in every language; only the purpose is
  translated.
- Linked from sign-up (next to the age confirmation), from Settings (the
  new «Τα δεδομένα σου» / "Your data" section), from the About page footer,
  the sitemap (`PUBLIC_PAGES`) and Health Connect's privacy link
  (`palee_health_privacy_path` = `/privacy#health`).

### 2. Minimum age 16: an explicit confirmation, enforced in the API
- Sign-up already collects display name, @handle, email, password and,
  optionally, an invitation code and a photo. It does **not** ask for a
  date of birth, and the data inventory lists "Date of birth" under "not
  collected".
- Chosen: one required checkbox «Είμαι 16 ετών ή μεγαλύτερος/η» / "I am 16
  or older", sent as `age_confirmed: true`. Rejected: a date of birth
  (`ui/DateInput`). Palee needs only the yes/no, never the date (data
  minimisation, article 5(1)(c)); a date would become a new data category
  in the privacy manifest and the store forms, and it is no more
  verifiable than the checkbox.
- Enforced in the domain (`Identity.Domain.AgePolicy`), called by
  `RegisterProfile` for every sign-up (`/auth/register`,
  `/auth/register-member`, `/auth/register-admin`) before anything is
  looked up: without it the answer is 422 `validation_failed` with
  `errors.age_confirmed = ["minimum_age"]` and nothing is created. The form
  shows the plain error under the checkbox (ADR-214).
- `logins.age_confirmed_at` keeps when it was confirmed (the first time
  only; empty for logins made before this rule, demo people and profiles
  held by an import).

### 3. "Download my data" («Λήψη των δεδομένων μου»)
- A new bounded context `Palee.PersonalData` with the table
  `personal_data_exports` (personal: forced row-level security, owner
  policy on `app.user_id`; a partial unique index allows one pending
  request per profile).
- `POST /api/me/data-exports` records a request and queues
  `PersonalDataExportJob` (Oban, the journal export's pattern).
  `GET /api/me/data-exports` lists them; a ready file gets a short-lived
  presigned link (the object store's 15 minutes), made afresh on every
  call, for 7 days.
- Rate limits: one in progress (409 `export_in_progress`), one a day
  (429 `export_rate_limited` with `retry_at` and `Retry-After`; a failed
  build does not count), and at most 5 POSTs an hour per person at the
  router.
- The job gathers the profile's own rows with the catalog
  (`PersonalData.Domain.Catalog`): each entry names a table, its archive
  file and how the person's rows are found (`{:eq, column}`, `{:in, …}`
  through a parent table, `{:any, …}`). Account entries are read in the
  person's own session; business entries once per business the person
  belongs or belonged to, in that business's session with the person
  acting — so row-level security applies exactly as for the person's own
  requests, and the query itself also filters on the person.
- Sections: profile, bookings, training (journal), wellness, devices,
  messages (only those the person wrote), community, payments, fiscal
  documents (receipts of the person's payments and invoices), signatures
  (signed documents, signature requests, health certificate dates).
- Never exported: any column named like a password, secret, token, PKCE,
  OAuth state, push key, API key or idempotency key; who on the staff acted
  (`*_by_id`); the other party of a conversation or block; storage keys of
  files. Provider keys are never read (ADR-246).
- The result is one ZIP of pretty JSON (`manifest.json` plus one
  `<section>.json` of `{table: [rows]}`), stored privately under the
  person's own storage prefix. The email outbox (ADR-203) sends
  `personal_data_export_ready` in the person's language; it has no
  download link, only the way to Settings (`/me/settings#your-data`).

## Rationale
- A checkbox is the least intrusive control that the API can enforce; a
  date of birth would add personal data without adding certainty.
- One catalog is easy to review against the privacy policy, and a test
  checks every table and column against the real schema, so a rename
  cannot silently drop data from the export.
- Reading through the person's own sessions reuses the tenancy model
  instead of a privileged path; the job never needs `admin_mode` or a
  vendor session.
- A link in the email would be a bearer token to health data in a mailbox;
  the signed-in Settings page is the only place a download link exists.

## Alternatives Considered
- **Date of birth with `ui/DateInput`:** more data, same assurance; would
  change the App Privacy / Data safety answers. Rejected.
- **Each context exporting its own personal rows** (like ADR-117's
  `export_tenant_data/2`): the right long-term shape, but forty contexts
  would change for one feature, and most personal tables are not in any
  tenant policy. The catalog can be split per context later without
  changing the archive format.
- **Including the photo and file binaries in the ZIP:** large and slow for
  one request; the archive lists the stored objects (media manifest) and
  the person can download each from the app. Follow-up if asked.
- **A signed download link in the email:** see Rationale.

## Consequences
- Every sign-up client must send `age_confirmed: true`; the three web forms
  do (personal sign-up, business sign-up for a new account, the owner
  invitation `/set-admin`), with `AgeConfirmationField` and its error under
  the box. The native apps load the web app, so nothing else changes.
- New tables with personal data should get a catalog entry; the schema
  test only proves that what is listed exists, not that everything is
  listed.
- The legal texts are drafts. Before submission the law consultant fills in
  the controller, contact, hosting provider, DPO (if any) and supervisory
  authority, and confirms the retention periods and the legal bases.
- Ontology rows: Privacy policy / Πολιτική απορρήτου, Terms of use / Όροι
  χρήσης, Your data / Τα δεδομένα σου, Download my data / Λήψη των
  δεδομένων μου, Data file / Αρχείο δεδομένων, Minimum age / Ελάχιστη
  ηλικία, Sub-processor / Εκτελών την επεξεργασία.

## Implementation Notes
- Migration `20270305000000_personal_data_exports_and_age_confirmation`.
- `personal_data/export_store` and `personal_data/record_source` are in
  `mix palee.architecture`'s tenant-scoped stores; the table is in the
  tenancy audit's personal tables.
- Profiles a CSV import holds (ADR-254) and demo people (ADR-184) are made
  by staff, not by sign-up, so they carry no age confirmation. A held
  profile is released when its login's email is verified, without a
  sign-up form: asking the age there is open (product owner).
