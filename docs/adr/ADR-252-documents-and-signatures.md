# ADR-252: Documents, simple electronic signatures and health certificates
Date: 2026-10-29
Status: Accepted

## Context
V3-M8 (CP-B1) is a pilot blocker. Boxes have clients sign a waiver, terms
and a privacy notice before they train, often on paper. In Greece a private
gym also needs a health certificate from each client, signed by a GP or
cardiologist (a paediatrician up to 16). It is valid for one year and is
needed both to join and to renew.

Two legal facts shape the design:

- **eIDAS article 25.** A simple electronic signature cannot be denied legal
  effect just because it is electronic. How much it proves depends on the
  evidence kept: what text was signed, by whom, when and from where.
- **GDPR article 9.** A health certificate is special-category data. Palee
  must hold as little of it as possible, and only staff who need it may see
  it.

Sources:

- eIDAS: https://www.axiocap.com/en/legal-summary/legal-regime-electronic-signatures and https://validsign.eu/resources/legislation
- Draft law, article 72: https://www.opengov.gr/cultureathl/?p=6928
- Kallithea gym regulation: https://kallithea.gr/wp-content/uploads/2024/10/ΕΣΩΤΕΡΙΚΟΣ-ΚΑΝΟΝΙΣΜΟΣ-ΓΥΜΝΑΣΤΗΡΙΟΥ2.pdf

## Decision

### 1. Documents and versions
A new context, `Palee.Documents`, with tables
`document_templates`, `document_versions` and `document_settings`.

- **Template.** Each template has a `kind`: `waiver`, `terms`, `privacy`,
  `health_certificate` or `other`. It also has a title, a status
  (`active`/`archived`) and a **requirement** set by staff:
  - Only `mandatory` documents count as outstanding and can block booking.
  - `optional` ones are only offered.
- **Versions are immutable.** Each holds the title, body (≤ 100k characters,
  line endings normalised), language and a SHA-256 `content_hash`. The hash
  covers the canonical JSON of template id, number, title, language and body.
- **Major and minor versions.** Each version is `major` or `minor`. Version 1
  is always major, and later versions are major unless staff choose otherwise.
  - A major version moves `required_version_number`, so everyone must sign
    again.
  - A minor version (a typo or wording fix) keeps earlier signatures valid.
- **Audit.** Creating a template, publishing a version, changing the
  requirement, archiving, and changing settings are written to
  `document_audit_events`, which is insert-only.

### 2. Signature requests
`document_signature_requests` holds one row per person. A bulk send shares a
`batch_id` and records its audience:

| Audience | Who receives it |
|---|---|
| `person` | one client |
| `all_clients` | every client |
| `role` | clients with the role `member` or `athlete` |
| `package` | clients whose subscription to the package is current today |

`Finance.package_holder_user_ids/3` was added for the `package` audience.

- People who already signed the required version are skipped.
- A partial unique index allows only one pending request per person and
  document.
- Each new request sends the `document_signature_requested` notification
  (category "account", gettext in all 12 locales).
- Signing closes the request. Archiving a template cancels its requests.

### 3. Signing (simple electronic signature)
`POST /me/documents/:id/sign` takes:

- `version_id`, which must be the current version (otherwise
  `document_version_outdated`);
- `agreed: true`;
- a typed name (2–120 characters) and/or a drawn signature. A drawn signature
  is vector strokes with integer coordinates inside its box, at most
  100 strokes and 5,000 points. Palee never accepts an image upload as a
  signature.

The evidence is canonical JSON:

- signature, organization, template and version ids, and the version number;
- the `content_hash` of the exact text;
- `signed_at` in microseconds;
- level and provider;
- the account (id, name, handle, e-mail);
- typed name and drawn strokes;
- IP address and user agent (up to 512 characters).

Its SHA-256 is stored as `evidence_hash`. `document_signatures` stores the
evidence columns, the hash, and the key, SHA-256 and size of the stored PDF.
The table is insert-only. User ids are plain columns, not foreign keys, so the
evidence outlives the account.

The signature that counts for a person is the one on the newest version they
signed. A document's status for a person is `signed`, `resign_required` or
`unsigned`.

**Order of work.** First the PDF certificate is rendered, sealed and stored.
Then a short transaction locks the template, checks again that the version is
still current, inserts the signature and closes the requests. If a version is
published in between, the stored PDF is left orphaned inside the tenant prefix
and the purge removes it.

### 4. The PDF certificate and the evidence store
There are two ports:

- `Documents.Ports.CertificateRenderer` renders the certificate. Adapter:
  `PdfCertificateRenderer`.
- `Documents.Ports.SignatureEvidenceStore` has `level/0`, `provider/0`,
  `seal/3`, `store/3` and `download_url/2`. Adapter:
  `StorageSignatureEvidenceStore`. It reports level `simple` and provider
  `palee`. `seal` passes the PDF through unchanged. `store` writes through the
  existing `TenantObjectStorage` at `documents/evidence/<signature id>.pdf`.
  An advanced or qualified provider (a PAdES seal, or a QTSP such as ValidSign
  or Docusign) later becomes one more adapter behind the same port.

The certificate has:

- a header (business, document, version, date in the box's time zone);
- the full text that was signed;
- the evidence table with both hashes;
- the drawn signature, redrawn from its strokes;
- a footer on each page.

Its labels are in the document's language (Greek or English).

**PDF writer.** No PDF library existed in the stack: receipts are HTML and
invoices use jsPDF in the browser. A Greek PDF needs an embedded Unicode font,
and pulling in a large dependency (or a headless browser) for one page type was
not justified. So `Infrastructure.Documents.Pdf.Writer` and `TrueType` write
PDF 1.7 directly:

- DejaVu Sans (already shipped by the web app; its licence is copied to
  `priv/fonts/`) embedded as a subset, Type0/CIDFontType2, Identity-H, with a
  ToUnicode CMap so text can be copied and searched;
- FlateDecode streams;
- deterministic output: the same evidence gives the same bytes.

A certificate is about 30 KB. Tests check the cross-reference table, the
subset, and that the output is deterministic.

### 5. Health certificates
`health_certificates` keeps **only** the issue date, the expiry date, the
file, its type and size, the uploader, and `reminded_for`.

- **Files.** PDF, JPEG, PNG or WebP up to 10 MB, uploaded with a presigned
  PUT under `organizations/<id>/health-certificates/<user id>/`. Palee checks the
  first bytes before recording the file.
- **Expiry.** It defaults to the issue date plus the box's validity months
  (12 by default, from 1 to 24). Validation refuses:

  | Case | Error |
  |---|---|
  | issue date in the future | `in_future` |
  | expiry before the issue date | `before_issue` |
  | expiry more than 24 months after issue | `too_late` |
  | certificate already expired | `already_expired` |

- **Status** is `missing`, `valid`, `expiring` (within the reminder window) or
  `expired` (on or after the expiry date).
- **Who sees what:**
  - The owner of the certificate sees their own file.
  - Staff with the new `manage_health_certificates` capability see every row
    and file. Each file view is audited as `health_certificate_viewed`.
  - Coaches (`view_health`, limited to their own clients) see only `valid` or
    `expired`, without dates or the file.
- **Reminders.** A daily job (`HealthCertificateRemindersJob`, 08:45 UTC)
  reminds clients once per certificate and expiry date. It runs only when the
  box requires certificates, and starts 30 days before expiry by default. The
  notification is `health_certificate_expiring`.

### 6. Booking gate
`Application.Documents.BookingGate.check/3` runs in four places:

- `SubmitBooking`;
- `JoinClassWaitlist`;
- `BookAppointment`, when a client books for themselves;
- `PlaceMemberInClass`, with `documents_gate: false`, so staff decide and are
  never blocked.

It checks clients only. A blocked request gets **409** with code
`documents_required` and `params: {documents: [{template_id, title, kind,
reason}], health_certificate}`.

Each box sets the gate in `document_settings`:

| Setting | Default |
|---|---|
| `block_booking_on_unsigned` (mandatory documents) | **on** |
| `block_booking_on_health_certificate` | **off** |

Turning on the health-certificate block also turns on
`health_certificate_required`.

### 7. Capabilities
| Area | Capabilities that grant access | Why |
|---|---|---|
| Documents: templates, versions, settings, audit | `manage_settings` | Writing the box's documents is a setting of the business. |
| Requests, signatures, evidence, a client's documents | `manage_settings` or `manage_memberships` | The people who enrol clients chase their signatures. |
| Health certificates: full rows and files | **`manage_health_certificates`** (new) | Art. 9 data needs a right of its own, not one bundled with settings. |
| Health certificates: status only | `view_health` (coaches, own clients) | Coaches need to know a certificate is valid, not what it says. |

`manage_health_certificates` belongs to owner and admin. A box can grant it to
front desk. The web role editor and its 12 translations were updated.

### 8. Endpoints
Staff endpoints are under `/api/org/:slug/admin/documents`:

- templates (list, create, show, version, publish, requirement, archive,
  requests);
- starters;
- requests (list, cancel);
- signatures and evidence;
- members/:user_id;
- settings;
- audit;
- health-certificates (list, a member's, uploads, create, file, delete).

Member endpoints are under `/api/org/:slug/me/documents`:

- overview;
- `/:id`;
- `/:id/sign`;
- signatures and evidence;
- health-certificate (uploads, create, file, delete).

Every operation has an OpenAPI spec, and the generated web client is
regenerated.

### 9. Starter drafts
`priv/documents/starters/{el,en}/` holds a waiver, terms, a privacy notice and
a health declaration. Every starter is marked `draft: true` and
`legal_review_required: true` and opens with «ΠΡΟΣΧΕΔΙΟ ΓΙΑ ΝΟΜΙΚΟ ΕΛΕΓΧΟ» /
"DRAFT FOR LEGAL REVIEW". They are not legal advice. A box copies one, edits
it and publishes it as its own document.

### 10. Tenant data and retention
Every table has forced RLS on `app.organization_id` and the
`palee_apply_tenant_context` trigger.

- **Insert-only rows.** Versions, signatures and audit events refuse UPDATE
  and DELETE (`palee_documents_immutable()`, pinned to `search_path` only).
  The exception is a DELETE in a transaction that sets
  `palee.documents_purge`.
- **Tenant-data policy.** Context `documents`, purge order 83.
  - Retained for **5 years**: templates, versions, signature requests,
    signatures, audit events, and the certificate PDFs under
    `documents/evidence/`.
  - Not retained: health certificates and settings (art. 9 minimisation).

## Rationale
- **Simple signature now.** It is what the research row asks for. It has legal
  effect under eIDAS art. 25, and its strength comes from the evidence chain,
  which this design keeps complete and tamper-evident: the hash of the exact
  text, the evidence hash and the stored PDF hash. The two ports keep the door
  open for a provider later.
- **Major and minor versions per publish.** Re-signing for a typo annoys every
  client, but a real change must not slip through. The publisher decides, and
  major is the default.
- **Status for coaches.** Coaches see valid or expired only, which is the
  smallest disclosure that still lets a coach act.

## Alternatives Considered
- **An external e-signature provider (Docusign, ValidSign) from day one.** It
  costs money per signature and adds onboarding. An advanced signature is not
  needed for a waiver. Rejected for now; the port is kept.
- **Rendering the PDF in the browser (jsPDF) or with a headless Chrome.** A
  certificate made in the browser is not trustworthy evidence, and a headless
  Chrome is heavy to operate. Rejected.
- **Storing the signature as a PNG.** Strokes are smaller, can be validated,
  and redraw sharply in the PDF. Rejected.
- **Health certificate as an ordinary signed document.** The data, its access
  and its expiry are different. Rejected.

## Consequences
- **The booking gate is on by default.** A box that publishes a mandatory
  document blocks its clients' bookings until they sign. The admin UI must say
  so when staff publish (follow-up UI milestone).
- **Front desk cannot see health certificate files** unless the box grants
  `manage_health_certificates`. With only the default rights, front desk
  cannot send signature requests either.
- **Deleting an account** removes that person's health certificate rows (FK
  `delete_all`) but not their files. The files stay under the tenant prefix
  until the tenant purge. Follow-up: an account-deletion hook.
- **Paediatricians.** The rule that a paediatrician can certify a child up to
  16 is not modelled. The certificate does not record who signed it, as data
  minimisation requires.

## Implementation Notes
- Migration: `20270208000000_create_documents.exs`. It adds the two
  notification types by rewriting `notifications_type_check` (read the
  current list, add or remove the types, write it back).
- Booking results use the 3-tuple `{:error, :documents_required, details}`.
  The FallbackController renders it like the package contract errors. The
  storage and renderer errors map to `503 signature_evidence_unavailable`.
- The latest-signature query orders by version number before time, so that
  two signatures at the same instant resolve to the newer version.
