# ADR-142: The gym's public profile, drafts and canonical tags
Date: 2026-10-19
Status: Accepted (P2-M1 part; public read API and follows land in P2-M2)

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

## Rationale
A snapshot makes «Δημοσίευση» a real moment and lets owners work in several
sittings. Canonical keys keep search, filters and translations consistent;
free-text tags would fragment the same thing into many spellings.

## Alternatives Considered
- A `published` boolean on the live row (the earlier version): every keystroke
  was public.
- Free-text tags with moderation: inconsistent filters and no translations.

## Consequences
- Adding a tag is a code change plus 12 translations.
- Migration `20261019100000` renames audiences `women`→`women_only`,
  `prenatal`→`prenatal_postnatal` and moves `kids` from disciplines to
  audiences, in profiles and class types.
