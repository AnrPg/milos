# ADR-065: Private Document Export and System Sharing
Date: 2026-07-18
Status: Accepted

## Context
Admins need to export workout definitions from the private workout library, while
authenticated users need equivalent controls for their own completed-workout
history and Pantheon personal records. Each surface must support PDF, Markdown,
plain text, OpenDocument Text, and CSV without filling cards with destination-
specific buttons. Users also want to send the artifact by email, save it to
Google Drive, Microsoft OneDrive, or Apple iCloud Drive, and share it through
social applications.

The source records remain owned by Workouts, Execution, and Pantheon. Creating
public share URLs or uploading records through a new server aggregate would
expand their authorization and retention boundaries. Browser and operating-
system share targets already provide the common privacy-preserving handoff to
email, cloud-drive, and social applications, but file-share support varies by
browser and installed applications.

## Decision
Introduce one reusable frontend Share / Export dialog backed by a canonical,
presentation-ready document model. Source adapters map an authorized admin
workout, the signed-in user's complete execution history, or the signed-in
user's complete Pantheon list into that model. Format renderers then generate
PDF, Markdown, text, ODT, or CSV locally in the browser.

PR and WOD card share controls are a separate in-app messaging workflow for one
record. They do not open file-export controls.

The dialog exposes exactly two selectors, one for format and one for delivery
destination, followed by one Export action. Delivery behavior is:

1. Download saves the generated file directly.
2. Share uses the Web Share API with a real `File`, allowing installed email,
   Google Drive, OneDrive, iCloud Drive, and social share targets to receive it.
3. Explicit destinations use the same file-capable system share sheet when
   available. Where it is unavailable, email receives the full rendered content
   in a `mailto:` composer, cloud-drive actions open the provider's upload
   surface before downloading the artifact, and social/other-app actions invoke a
   text-capable system share with the complete rendered content. If no system
   share API exists, that content is copied to the clipboard. Social fallback
   never silently redirects to a local download.

PDF generation uses `jspdf`. Standards-compliant ODT files use `jszip` to build
the required OpenDocument package with an uncompressed first `mimetype` entry.
Markdown, text, and CSV renderers remain dependency-free.

Admin workout-library controls remain under the existing admin-only route and
operate only on records already returned by its authorized API. WOD history and
Pantheon controls operate only on records returned for the current authenticated
user. Generated blobs are ephemeral and are not uploaded to Milos Training or a
conversion service.

## Rationale
A shared document model keeps format behavior consistent without coupling UI
components to one another or duplicating serializers across three screens.
Local generation preserves privacy, works without a new backend endpoint, and
avoids inventing cross-context persistence for transient artifacts.

The system share sheet is the only portable web capability that can hand an
actual file to Apple, Microsoft, Google, email, and social applications without
storing provider OAuth grants in Milos Training. Explicit fallbacks keep the
feature useful on desktop browsers that do not implement file sharing.

## Alternatives Considered
Server-generated artifacts were rejected because the data is already available
through authorized read models and a server workflow would add storage,
cleanup, authorization, and email/provider credential concerns.

Public share links were rejected because they would require a new revocation,
expiry, access-control, and privacy model for workout definitions and personal
training results.

Separate Google Drive, Microsoft Graph, and social-network integrations were
rejected for this slice because each requires provider registration, OAuth token
storage, scopes, revocation, and operational secrets, while Apple provides no
equivalent general-purpose web upload API for iCloud Drive. The system share
sheet covers all installed targets under user control.

HTML files renamed as PDF or ODT were rejected because the exported extensions
must contain valid artifacts consumable by standard readers.

## Consequences
File-capable system sharing depends on browser support and installed share
targets. The dialog must explain when it used a download, mail composer, cloud
upload page, or clipboard fallback instead.

The frontend gains two runtime dependencies and focused serializer/dialog tests.
Large records are generated in memory, so renderers must avoid retaining blobs
after the action completes.

CSV is a flattened interoperability format and cannot preserve the same visual
hierarchy as PDF, ODT, Markdown, or text. The canonical row contract must remain
stable enough for spreadsheet import.

## Implementation Notes
Implemented on 2026-07-18 with a single `ShareExportDialog` used by the admin
workout library, the current user's complete WOD history, and the current user's
complete Pantheon PR list. A follow-up correction on the same date separated
single-record card sharing into a compact authenticated Milos direct-message
dialog and reduced collection export to two selectors plus one action.

The canonical export model has source adapters for materialized workouts,
editable workout drafts, executions, and PRs. Draft normalization is deliberately
limited to the existing workout-draft contract and does not create a second
domain model. The renderers generate real PDF and ODT containers; PDF and ODT
use a violet, teal, pink, slate visual hierarchy, while Unicode-capable ODT,
Markdown, and text outputs include contextual emoji. CSV remains BOM-prefixed,
quoted, and hierarchy-flattened for spreadsheet interoperability.

The Web Share path passes the generated `File` itself in the selected format and
also supplies the complete rendered document as share text. Provider choices
reuse that path when the browser supports file sharing. Unsupported social and
general-app destinations share the complete text instead of downloading; email
uses that text as its body. Cloud destinations open the chosen provider before
starting the local download because browsers do not permit one website to inject
a local file into another provider's page without a provider integration.

Verification completed with 56 frontend tests, including real PDF signatures,
ODT package/color/emoji assertions, draft-workout content, and selected-format
file handoff; TypeScript, targeted ESLint, the production Next.js build, and the
localization gates all pass. The localization catalog contains 2,303 matching
messages across all 12 supported locales with no hard-coded TSX copy. A local
production server smoke test returned HTTP 200 for `/` and `/admin/workouts`.
No new technical-debt entry was created: direct provider OAuth integrations are
an explicitly rejected alternative, not incomplete work in this implementation.
