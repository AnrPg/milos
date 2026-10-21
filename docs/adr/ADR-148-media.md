# ADR-148: Media uploads
Date: 2026-10-19
Status: Accepted

## Context
Phase 2 adds photos: the gym's public page now, posts and body photos later.
Images must never leak location metadata and must not linger unattached.

## Decision
1. `media_objects` with scope `account` or `tenant` and a purpose
   (`box_photo`, `post_photo`, `body_photo`). Upload is a presigned PUT, then
   `CompleteMediaUpload` checks size and type and rejects (and deletes) any file
   whose markers still carry EXIF or XMP; only then is it `ready`.
2. The web re-encodes every image before upload (canvas, WebP or JPEG, at most
   2400 px on the long edge), which drops EXIF and GPS.
3. `SweepOrphanMedia` deletes uploads that nothing references after a day.

## Rationale
Client re-encoding removes metadata at the source; the server check makes it
a guarantee instead of a convention.

## Alternatives Considered
Server-side re-encoding: CPU on the API and the original still travels.

## Consequences
Uploads need a browser with canvas encoding (all supported ones have it).

## Implementation Notes
Migration `20261018101000_media_and_public_profiles`; web helper
`src/lib/box-photo-upload.ts`.

ADR-157 (P2-M9): post photos and videos are the author's (account scope) and are
processed on the server (metadata stripped, renditions); box photos keep this path.
