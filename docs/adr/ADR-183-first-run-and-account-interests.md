# ADR-183: The member first-run and account interests
Date: 2026-10-23
Status: Accepted

## Context
Palee is now a social app for active people, but a new account landed on an empty Home:
nothing asked for a photo, what the person trains, where they are, or whether they already
belong to a box. Γύρω μου, Partners and suggestions had nothing to start from. ANR approved
a short, skippable first-run after sign-up (doc "Sign-up, staff, branches and event
organisers", §2). Sign-up itself (email, password, display name, @handle) belongs to
ADR-187, from the identity work.

## Decision
1. **A first-run at `/welcome`, three skippable steps.** (1) Profile photo, with the display
   name from sign-up already shown. (2) «Τι κάνεις»: disciplines and a level. (3) «Πού
   προπονείσαι»: «Η περιοχή μου» (ADR-154, the existing `AreaPicker`) and «Είσαι ήδη σε box;»:
   find a box nearby (Γύρω μου › boxes), redeem an invite code (`POST /memberships/redeem`),
   or "not yet". Someone who already holds a membership sees which box they are in instead.
2. **It shows once per account, on any device.** Finishing or skipping records the
   `first_run` audience in `users.completed_tours` (ADR-107's tour mechanism). Home (`/`)
   sends an account without it to `/welcome`; a session flag covers the moments before
   `/auth/me` is read again. The migration gives `first_run` to every existing account, so
   only new accounts see it. Vendors never see it. `?next=` is followed only for same-site
   paths. Arriving through an invite, join or event link goes straight there. The first-run
   then waits until the person first opens Home.
3. **Interests are their own context and table.** `Palee.Interests` (port, RepoContext facade,
   Ecto adapter) owns `account_interests(user_id PK, disciplines text[], level, timestamps)`,
   one row per account (per profile under ADR-187). Personal data: an owner-only RLS policy,
   and it's listed among `Tenancy.Audit`'s ready personal tables and the architecture task's
   tenant-scoped stores. Account deletion cascades.
4. **Shared vocabularies, not new ones.** Disciplines are keys of the box vocabulary
   (ADR-142, `GET /box-vocabulary`), so what a person does and what a box offers meet in
   Γύρω μου. Levels are the Partners levels (ADR-169). At most 12 disciplines. Order is the
   person's, and duplicates collapse.
5. **API.** `GET /api/me/interests` returns `{disciplines: [], level: null}` until set.
   `PUT /api/me/interests` replaces both, and both keys are required (`level` may be null).
   Unknown keys answer 422 `validation_failed`.
6. **Interests suggest and never filter.** Readers may rank or offer a one-tap filter from
   them. Nothing is hidden because of them.

## Rationale
Reusing the tour list keeps "seen once, everywhere" in one place, with no new column on
`users`, the table the identity work is reshaping. A separate context keeps interests out of
Identity and lets Γύρω μου, Partners and Feed read them through one port.

## Alternatives Considered
- Interests as columns on `users`: couples a social preference to the account table and
  collides with ADR-187's migration.
- A local-storage flag for the first-run: shows again on every new device.
- One long sign-up form: lower completion, and it feels like a gym system.

## Consequences
- Γύρω μου leads its chip row with «Τα αθλήματά μου» (one tap sets the discipline filter to the person's interests, a second clears it) and lists their disciplines first in the discipline chip. Partners may prefill from them later.
- Εγώ › «Τι κάνεις» (`/me/settings/interests`) edits them any time with the same editor as the first-run (`InterestsEditor`).

## Implementation Notes
- `ProductTours` gains `first_run`. The tour path parameter and `completed_tours` enums read
  `Identity.tour_audiences/0`, so the next audience is one edit.
- The first-run hides the product-tour host (`/welcome` is in its hidden paths).
