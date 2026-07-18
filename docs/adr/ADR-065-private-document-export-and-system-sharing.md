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
workout, the signed-in user's execution record, or the signed-in user's PR into
that model. Format renderers then generate PDF, Markdown, text, ODT, or CSV
locally in the browser.

The dialog exposes one selected format and three delivery paths:

1. Download saves the generated file directly.
2. Share uses the Web Share API with a real `File`, allowing installed email,
   Google Drive, OneDrive, iCloud Drive, and social share targets to receive it.
3. Explicit destination shortcuts use the same file-capable system share sheet
   when available. Where it is unavailable, email receives a localized plain-
   text `mailto:` fallback and cloud-drive actions download the artifact before
   opening the provider's upload surface. Social fallback copies a plain-text
   summary for pasting without creating a public application URL.

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
To be completed after implementation and live verification.
