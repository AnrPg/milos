# ADR-231: The profile's «Πολυμέσα» grid
Date: 2026-10-29
Status: Accepted

## Context
ANR (2026-10-29): a person's profile, as others see it, should have a tab
with only their photos, videos and reels, like Instagram. Palee has no
separate reel object: since ADR-157 a post carries up to ten photos or one
video (≤2 minutes), so «reels» are posts with a video. The profile tabs were
«Αναρτήσεις · PRs · Clubs» (vision §7.11); Εγώ shows the same profile.

## Decision
1. A **Πολυμέσα** tab (en "Media") after Αναρτήσεις, on a person's profile
   (`/people/:id?tab=media`) and on Εγώ (with its count).
2. `GET /api/people/:id/media` returns the person's profile posts that carry
   media (`cardinality(media) > 0`), newest first, 30 a page (ten grid rows),
   in the `PersonPostsResponse` shape. It runs through the same
   `list_profile_posts` read as `/posts` with a `media_only` filter, so the
   posts' RLS audience, ADR-157's "not ready = author only" and ADR-184's mock
   people rules apply unchanged; a private account's followers posts stay
   hidden behind the same lock note.
3. `GET /api/me/social` adds `media_count` (ready posts with media).
4. The web grid is three-wide squares of the first photo's `thumb_url` (a
   video's poster) over its blurred placeholder, with a corner mark for a
   video (and its length) or an album. A square opens the post in the
   dialog shell (ADR-177) as a `PostCard`, so the viewer, kudos and comments
   are the feed's own.
5. A partial index `(user_id, inserted_at, id) WHERE deleted_at IS NULL AND
   cardinality(media) > 0` serves the grid.

## Alternatives Considered
- Separate Photos / Videos («Reels») tabs: more UI for little gain while a
  video is one per post; a filter can be added to this endpoint later.
- Filtering media on the client from `/posts`: pages of text posts would
  yield empty grid pages and waste reads.
- A media-item endpoint (one square per photo): Instagram shows one square
  per post; opening the post keeps its words, kudos and comments together.

## Consequences
- Club posts stay out of the profile grid, as they stay out of Αναρτήσεις.
- Thumbnails are presigned (15 minutes, ADR-157); the grid refetches with
  the person's queries.

## Implementation Notes
Migration `20261230100000_profile_media_grid_index`. API:
`SocialProfile.media/3`, `PeopleController.media`, store filter
`media_only`. Web: `components/social/MediaGrid.tsx`, `mediaTile` and
`personTab` in `social-model.ts`.
