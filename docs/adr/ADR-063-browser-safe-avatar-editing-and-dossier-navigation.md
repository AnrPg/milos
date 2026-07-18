# ADR-063: Browser-safe avatar editing and dossier navigation
Date: 2026-07-18
Status: Accepted

## Context
Profile avatar uploads were sent directly from the browser to MinIO with a presigned `Content-Length` header. Browsers do not allow application code to set that header, and the deployment did not make its cross-origin media policy explicit. The file picker also accepted formats rejected by the API and uploaded immediately, so members could neither understand failures nor frame their image before saving it.

Admin user dossiers also treated section chips as plain anchors. They scrolled to a section but did not guarantee that a collapsed panel opened, while padding outside the panel header button left part of a collapsed title card non-interactive.

## Decision
Avatar uploads remain direct, presigned MinIO PUTs, but only `Content-Type` is signed and returned as a browser-settable required header. The MinIO service explicitly configures its supported API CORS origin setting. The API verifies the uploaded object's actual type, size, and user-scoped key before accepting it; metadata is read with a bounded one-byte ranged GET because this MinIO/Hackney combination cannot safely process bodyless HEAD responses.

The web profile accepts only JPEG, PNG, and WebP images up to 5 MiB, opens a local canvas editor for zooming and horizontal/vertical framing, and uploads a normalized square JPEG only after confirmation. Profile edits receive a persistent, explicit form-associated “Save changes” action.

Admin dossier panels retain local disclosure state but listen for a typed section-open request. Section chips issue that request before scrolling, including repeated clicks on the current hash. Panel header buttons occupy the complete collapsed card surface.

## Rationale
Keeping presigned uploads avoids routing large binary bodies through Phoenix while removing headers browsers cannot control. Wildcard CORS does not grant write access: possession of a short-lived signed URL is still required, and final server-side validation remains authoritative. Client-side canvas editing adds no dependency and ensures the stored avatar matches the circular UI crop.

An explicit open-and-scroll event preserves each panel's independent disclosure behavior and handles repeated navigation to the same section, which native hash changes alone do not reliably signal.

## Alternatives Considered
- Proxy image bytes through Phoenix: rejected because it adds API bandwidth and multipart handling without improving validation.
- Sign `Content-Length` and rely on the browser to provide it automatically: rejected because the signature can diverge and JavaScript cannot set the forbidden header.
- Add an image-crop dependency: rejected because the required square crop, zoom, and positioning are small enough to implement with the existing canvas platform.
- Control every dossier panel from one parent state map: viable, but rejected as unnecessary coupling for a single open-and-scroll interaction.

## Consequences
Avatar objects are normalized to JPEG, so transparency is flattened against a neutral background. Presigned upload URLs remain security-sensitive until their fifteen-minute expiry. MinIO's service-wide CORS default is now explicit and may be narrowed through `MINIO_API_CORS_ALLOW_ORIGIN` in deployments with a fixed browser origin. Dossier deep links and chip clicks consistently reveal their content.

## Implementation Notes
MinIO `RELEASE.2025-09-07T16-13-09Z` returned HTTP 501 for the S3 bucket-CORS operation, so CORS is configured through the supported `MINIO_API_CORS_ALLOW_ORIGIN` service setting instead. A live preflight returned HTTP 204 with PUT and `content-type` allowed.

Live verification also exposed that ExAws/Hackney crashes on MinIO's valid bodyless HEAD response tuple. Avatar validation now uses `Range: bytes=0-0` and derives total size from `Content-Range`, bounding response data to one byte while preserving authoritative size checks. The signed PUT, metadata validation, public URL, and exact-object cleanup all passed against local MinIO.

The editor uses the browser canvas rather than a new package. It normalizes output to a 512 × 512 JPEG and provides zoom plus horizontal and vertical framing. The visible profile-level save button is associated to the personal-details form through the HTML `form` attribute, so it works outside the collapsible panel.
