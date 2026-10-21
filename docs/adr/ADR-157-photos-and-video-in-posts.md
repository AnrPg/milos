# ADR-157: Photos and video in posts
Date: 2026-10-20
Status: Accepted

## Context
Plan §5 P2-M9 and vision §7.1 ("optional media, text, optional workout
attachment") put photos and short videos in posts. ADR-148 built uploads
for box photos: the browser re-encodes, the server only checks that no
EXIF/XMP is left. Phones produce HEIC, huge JPEGs with GPS, and videos the
browser cannot re-encode, so posts need server-side processing.
ADR-156 is taken by member referrals (P2-M8, built in parallel), so this
is ADR-157. Decisions follow board 12 as ANR answered it: up to ten photos
or one video of up to two minutes, alt text with an AI suggestion, sharing
a PR, uploads while composing, and **no automatic moderation** (Q5 B):
safety rests on reports (ADR-143).

## Decision
1. **Post media belong to their author.** Purposes `post_photo` and
   `post_video` live in `media_account_objects` (key prefix `users/<id>/`),
   for club and profile posts alike. They go with the account, and a
   compose may change destination without re-uploading. `post_photo` left
   the gym-owned table (it never held one).
2. **Upload per file, as soon as it is picked.** `POST /api/me/media/uploads`
   (`purpose`, `content_type`, `byte_size`) returns a presigned PUT; `POST
   /api/me/media/:id/complete` checks the stored bytes (`ImageInspector.sniff`
   decides the real type: JPEG, PNG, WebP, HEIC/HEIF; MP4, QuickTime, WebM)
   and the size cap (photos 25 MB, videos 500 MB), then moves the upload to
   `processing`. Status: pending → processing → ready | rejected (with
   `rejection_reason`). A quota guard caps open uploads (30 a day) and
   stored bytes (5 GB) per person; a rate limit (60 writes / 5 min) sits in
   front.
3. **Processing in the background** (`ProcessMediaJob`, Oban queue `media`,
   2 workers) through two ports:
   - `ImageProcessor` (adapter `ImageMagickProcessor`, ImageMagick 6/7 CLI):
     probe first (a 50 MP decompression guard), then one decode that is
     turned upright, stripped of every profile (EXIF with GPS, XMP, IPTC)
     and written as WebP `thumb` 320, `feed` 1080 and `full` 2048 px on the
     long side, plus a 16 px WebP data-URI placeholder. The input coder is
     named from the sniffed type; resource limits and a wall-clock kill
     bound every run.
   - `VideoTranscoder` (adapter `FfmpegTranscoder`): ffprobe (at most 120 s),
     one H.264/AAC MP4 at most 1280 px on the long side, never upscaled,
     `+faststart`, `-map_metadata -1 -map_chapters -1`; its poster frame goes
     through the image pipeline.
   The original is deleted once renditions are stored. Failures that may
   pass are retried; the last attempt rejects.
4. **Posts carry media.** `media_ids` (≤10 photos xor 1 video, in order) on
   club and profile posts; a post may be published while its media still
   process. The post keeps an ordered snapshot (`media`, renditions with
   keys, sizes, placeholder, alt text, duration) and `media_status`
   (`ready` | `processing` | `failed`). Only its author (and moderators)
   see a post that is not `ready` («επεξεργάζεται»). `PostMedia.refresh/1`
   recomputes snapshot and status under a row lock whenever something
   changes (post created, upload processed or rejected, alt text edited);
   feeds never read media rows across people.
5. **Readers get** `media[]` with `thumb_url`, `feed_url`, `full_url`
   (for a video, its poster), `video_url`, `width`, `height`, `placeholder`,
   `alt_text`, `duration_ms`, signed for the author's prefix (short-lived
   presigned URLs, as ADR-148).
6. **Alt text.** `PATCH /api/me/media/:id` sets it (≤500 chars).
   `POST /api/me/media/:id/alt-text-suggestion` asks the `ImageDescriber`
   port (adapter `GeminiImageDescriber`, model `GEMINI_VISION_MODEL`) for one
   sentence in the asked language, else the person's, else Greek. The
   suggestion is returned only, never saved; usage is metered (ADR-152,
   feature `post_alt_text`), persisted when the call has a gym.
7. **No automatic moderation.** Every processed photo shows. Reports work
   on posts with media as before; the staff queue preview carries the
   post's media (thumbnails) and status.
8. **Sharing a PR.** Posts already took a `pr` attachment;
   `GET /api/me/post-attachments/:type/:id` returns the card a PR or journal
   entry makes, so the compose is prefilled right after a PR is logged. No
   auto-posting.
9. **Lifecycle.** Unattached uploads are swept after a day (ADR-148);
   attached uploads stuck before `ready` for a day are rejected (their post
   turns `failed`); daily, uploads attached to a post that is gone (a
   purged gym, a failed release) are released. Both lookups are narrow
   SECURITY DEFINER functions answering ids only. Deleting a post (by its
   author, a moderator or a report action) deletes its uploads and every
   rendition. Account deletion already purges `users/<id>/media/`.
10. `GET /api/me/media/capabilities` tells the compose the limits and
    whether this server takes videos (`video: false` where ffmpeg is
    missing; uploads of videos then answer 503 `video_unavailable`).

## Rationale
Server processing makes metadata removal a guarantee for any file a phone
produces, gives every reader the same small renditions, and keeps the
original off the servers. Keeping media with the author follows "private
by default" (vision §4.5) and GDPR: they leave with the person. A snapshot
on the post lets the existing post RLS decide who sees media and keeps feed
reads to one query per source.

## Alternatives Considered
- Client re-encoding (as ADR-148): cannot handle HEIC or video, and leaves
  the guarantee to a convention.
- libvips via `image`/`vix`: faster, but a NIF with a native build on
  Alpine; the ImageMagick CLI is available in both images and isolated in
  its own process.
- HLS renditions: more moving parts for ≤2-minute clips; one MP4 suffices.
- Reading media rows at feed time with RLS policies joining posts: couples
  RLS across contexts and costs a query per page per source.
- Automatic moderation of public photos (board 12 Q5 A): declined by ANR.

## Consequences
- The API image carries ImageMagick and ffmpeg (Dockerfile, Dockerfile.dev).
- Presigned URLs expire after 15 minutes; a CDN in front is future work.
- Wide-gamut photos are stripped of their ICC profile; colours may shift
  slightly.
- Alt text suggestions for profile posts are metered but not persisted
  (no gym to bill), as with any call without a tenant.
- Tenant export includes the posts' media snapshots, not the objects (they
  are the members').

## Implementation Notes
Migration `20261027100000_post_media` (columns on both media tables and on
`community_posts`/`community_profile_posts`, functions
`palee_dangling_post_media`, `palee_stale_post_media`). Config:
`:image_processor`, `:video_transcoder`, `:image_describer`; env
`GEMINI_API_KEY`, `GEMINI_VISION_MODEL`. Tests of the real adapters are
tagged `:imagemagick` / `:ffmpeg` and skipped where the tools are missing.
