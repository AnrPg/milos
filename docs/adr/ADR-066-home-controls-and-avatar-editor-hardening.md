# ADR-066: Home controls and avatar editor hardening
Date: 2026-07-18
Status: Accepted

## Context
The shared home history panels placed secondary action controls beside the section
title, making the Personal Records and WOD History headers visually crowded. The
avatar editor also used a centered fixed panel without a viewport height cap, so
small screens could crop the lower controls. Production avatar uploads could fail
before reaching storage because the web CSP only allowed the local media origin
unless the deployment explicitly passed the media origin into Next.js.

## Decision
Keep the home disclosure header limited to title and show/hide state, and render
PR/WOD action controls inside the expanded panel body. Extend the avatar canvas
editor with persisted rotation and a scrollable, max-height modal. Feed the media
origin into the web container and let the CSP helper accept a constrained
space/comma-separated list of media origins.

## Rationale
Moving list-specific controls into the panel body preserves the compact disclosure
header while keeping the actions close to the data they affect. Canvas-level
rotation ensures the uploaded JPEG matches the preview. A configured origin list
keeps CSP explicit while supporting both local Caddy-served MinIO and production
media hostnames.

## Alternatives Considered
- Keep header actions and reduce button sizes: rejected because the header still
  mixes section identity with list controls.
- Rotate only the preview element with CSS: rejected because it would not affect
  the generated upload file.
- Use `connect-src https:` for presigned uploads: rejected because the deployment
  only needs known media origins.

## Consequences
Deployments with a custom public MinIO/S3 origin must set `MINIO_PUBLIC_ENDPOINT`
or `NEXT_PUBLIC_MEDIA_ORIGIN` for the web CSP. The avatar editor now treats
rotation as part of the final normalized JPEG, so EXIF orientation plus manual
rotation are flattened into the stored image.

## Implementation Notes
The home page now renders Personal Records and WOD History controls inside the
expanded disclosure body. WOD view toggles gained localized accessible labels so
the icon-only controls remain understandable to assistive technology and browser
tooltips.

The avatar editor modal now caps itself to the viewport and scrolls internally,
with a slightly smaller preview on narrow screens. Rotation is applied in the
same canvas transform used to produce the normalized JPEG, so the uploaded file
matches the edited preview.

The web CSP now parses `NEXT_PUBLIC_MEDIA_ORIGIN` as a space- or comma-separated
origin list and the Compose web service receives it from deployment environment
configuration. This keeps presigned avatar/invoice upload access limited to
configured media origins while allowing production hosts such as a dedicated S3
or MinIO domain.
