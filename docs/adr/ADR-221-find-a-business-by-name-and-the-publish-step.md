# ADR-221: Find a box or coach by name; publishing the public page is a setup step
Date: 2026-10-28
Status: Accepted

## Context
ANR, as vendor, activated a client's business (ADR-184). Afterwards the
client's personal account was found in «Βρες», but the box was not, neither
in «Βρες» nor from the Box tab («Βρες box» → Γύρω μου). Two separate causes:

1. **No name search for businesses existed.** «Βρες» searched open clubs
   (only of boxes you already belong to or follow) and people (ADR-193 §4).
   Γύρω μου finds businesses only by place. A box someone already knows by
   name could not be found by typing it anywhere.
2. **Activation does not publish the page, by design.** A business is visible
   to visitors only when it is active, live (`activation = 'active'`) **and**
   has a published public page (ADR-142); Γύρω μου also needs an open
   location with a map point. In demo the page can only stay a draft
   (`GoLive :publish_profile`), and activation keeps that draft as it is. A
   gym's setup checklist had no step for the page (only a coach's had,
   ADR-170), and the activation screen did not say it, so the owner had no
   cue that one more step was needed.

## Decision
- **Name search** `GET /api/box-search?q=` (personal session, search rate
  limit): the SQL function `palee_search_public_boxes(terms, limit)` answers
  only for rows `palee_public_boxes` would (active, live, published). The
  name, brand name and slug are folded by `palee_fold_name` (NFKD, marks
  stripped, lower-case) and the query is folded the same way and also tried
  in its Latin form and hyphenated, so «Τολάρας», "τολαρας" and "tolaras"
  meet. Order: whole-name prefix, then a word prefix, then anywhere, then
  (from three characters) a close spelling by pg_trgm word similarity ≥ 0.5,
  like people and club search (ANR 2026-10-25). A map point is not needed.
  Each result carries the viewer's follow status.
- **Where it shows:** «Βρες» (placeholder and title now «clubs, box και
  άτομα») gets a «Box και coaches» card, shown only when something matches;
  the Box tab without a membership gets «Ή ψάξε με το όνομα» under
  «Βρες box». A row opens `/b/:slug` and has Follow.
- **The page is a setup step.** The gym checklist gains `page` («Δημοσίευσε
  τη δημόσια σελίδα σου») before `invite`, done automatically once the page
  is published. The activation success screen says the page is the next
  step and its main button opens the editor. The editor's «Πριν τη
  δημοσίευση» list adds «Διεύθυνση στον χάρτη» (`on_map` on the profile
  payload) with a link to the locations, and while the page is a draft a
  line says nobody finds the box yet.

## Rationale
Activation must not publish the page on its own: the page is public text and
photos the owner should review, and §4 keeps visibility the owner's choice.
So the fix is to make the existing requirement visible at the three places
the owner passes (activation, checklist, editor) and to add the missing way
to find a known business. The search reuses the visitor rules of the public
box page instead of a second definition of "public", so a box can never be
found by name yet 404 on its page.

## Alternatives Considered
- **Publish the draft on activation:** rejected (above); also fails when the
  draft is incomplete.
- **List live boxes without a published page:** rejected; there is nothing
  to show them with, and demo/unfinished businesses would leak.
- **A stored search key on organizations (like `users.search_text`):** the
  name lives in two tables (organization, brand name) and needs Elixir
  transliteration; folding in SQL plus the Latin slug covers the same cases
  without a trigger. Revisit with an index when businesses reach the tens of
  thousands.

## Consequences
- `AdminOnboardingChecklist` steps gain `page`; gyms have 8 steps.
- `BoxPublicProfile` gains `on_map`.
- Migration `20261225100000_box_name_search` (functions only, no data).
