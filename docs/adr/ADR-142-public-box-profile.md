# ADR-142: The gym's public profile, public page, follows and audiences
Date: 2026-10-19 (extended 2026-10-20 for P2-M2)
Status: Accepted

## Context
Before someone joins, they see the gym's «Σχετικά»: text, photos and what it
offers. Owners must be able to edit it without visitors seeing half-finished
work, and visitors must be able to filter gyms by the same words everywhere
(board 3, board 3b).

## Decision
1. **Draft and snapshot.** `organization_public_profiles` holds the draft
   (about, disciplines, services, audiences, languages, amenities,
   `cover_photo_id`, `photo_ids`). «Δημοσίευση» copies it into
   `published_snapshot`; visitors only ever read the snapshot. Publishing needs
   text and at least one discipline. Απόσυρση clears the snapshot and keeps the
   draft. Optimistic locking (`lock_version`) on every save and publish.
2. **Media lifetime.** A photo is released only when neither the draft nor the
   snapshot uses it, so dropping a photo from the draft never breaks the live
   page.
3. **Canonical vocabularies in code** (`BoxProfilePolicy`): 46 disciplines in 9
   groups, 12 audiences, 18 amenities, 6 services, served as keys at
   `GET /api/box-vocabulary` and translated in the web `BoxTags` namespace.
   Class types share the audience list. No "main disciplines" (board 3b).
   `returning_from_injury` requires `physio_rehab`.
4. **Suggestions, not free text.** «Δεν το βρίσκεις; Πρότεινέ το» stores a row
   in `profile_tag_suggestions` (tenant table, RLS). Platform staff review all
   gyms' suggestions through SECURITY DEFINER functions at
   `/api/platform/tag-suggestions`; adding a tag means adding it to the list in
   code, so every gym sees the same vocabulary.
5. **Editor** at `/admin/public-page`: steps Κείμενο, Φωτογραφίες (separate
   cover slot plus a gallery of up to 12), Τι προσφέρει, Για ποιους, Παροχές;
   tag cards open a grouped picker with search (side panel on wide screens,
   bottom sheet on phones). Visitors see only the tags the owner picked.
6. **Coaches (P2-M2, board 4 Q4).** The draft carries `coach_ids`, picked from
   the gym's staff (`Organizations.list_staff`) and published with the rest.
   The page shows a picked coach only while they are still on staff, with the
   class types they teach over the next four weeks.

### P2-M2: the public page, follows and audiences
7. **Public read.** `GET /api/public/boxes/:slug` (no account, own rate-limit
   bucket) returns the box, the published snapshot, open locations and the
   follower count. A slug or any retired alias resolves only for an active gym
   with a published page, through the SECURITY DEFINER functions
   `palee_public_box_by_slug` and `palee_public_boxes`; the read then runs in
   that gym's scope and projects only public fields.
8. **Sign-in for the rest (board 4 D2).** The schedule (a window of up to 31
   days, no bookings or member data) and the box's public posts are at
   `/api/boxes/:slug/schedule` and `/api/boxes/:slug/posts`, signed-in only.
   Logged-out visitors see «Σχετικά» and a sign-in prompt.
9. **Follows.** `community_follows` is account-scoped (the follower owns the
   row). A follow of a person starts `requested` and only that person can
   make it `active` (RLS: insert as requested, target-only update); boxes and,
   from P2-M4, open clubs are followed at once. Requests and acceptances are
   notifications (`follow_requested`, `follow_accepted`). Counts are public
   numbers through `palee_follow_counts` and `palee_following_count`.
10. **Audiences.** A club post is `club_channel` or, for staff only, `public`:
    it then also shows on the box page and to the box's followers (RLS read
    policies on posts, reactions and comments). A member's own voice lives in
    `community_profile_posts` with audience `followers` or `public`, so it
    follows them across gyms; an active follow is what opens a followers post.
11. **Feed.** `/api/me/feed` merges club posts, profile posts of the people the
    member follows and their own, and public posts of followed boxes the
    member does not belong to, ordered by `(inserted_at, id)` with one keyset
    cursor. Every post carries `origin` (`club` or `profile`) and `audience`.
12. **Bookings for followers (board 5 Q6, the «Φίλοι» chip).** Bookings stay
    private by default (vision §4.5). A member turns sharing on for all their
    followers in account-scoped `community_social_settings`, offered once after
    they accept their first follower and changeable in Κοινοποίηση &
    ορατότητα. The member schedule adds `friends_going` to each class: people
    the viewer actively follows who share and hold a place (pending or
    approved). Only the owner reads the settings row; `palee_booking_sharers()`
    (SECURITY DEFINER, bound to `app.user_id`) tells a follower who among the
    people they follow shares, and nothing more.

## Rationale
A snapshot makes «Δημοσίευση» a real moment and lets owners work in several
sittings. Canonical keys keep search, filters and translations consistent;
free-text tags would fragment the same thing into many spellings.

Account-scoped profile posts keep tenant tables free of rows with no
organization (the tenancy audit counts them) and keep a member's voice theirs
when they change gyms.

## Alternatives Considered
- A `published` boolean on the live row (the earlier version): every keystroke
  was public.
- Free-text tags with moderation: inconsistent filters and no translations.
- Profile posts as `community_posts` rows with a NULL organization: breaks
  tenant ownership and the audit.
- A public schedule and posts (the first board 4 draft): changed by the owner
  so the page invites sign-in.

## Consequences
- Adding a tag is a code change plus 12 translations.
- Migration `20261019100000` renames audiences `women`→`women_only`,
  `prenatal`→`prenatal_postnatal` and moves `kids` from disciplines to
  audiences, in profiles and class types.
- Migration `20261020100000` adds the public lookups, follows, profile posts
  and their policies, the public read policies on club posts and `coach_ids`.
- Migration `20261020110000` adds `community_social_settings` and
  `palee_booking_sharers()`.
