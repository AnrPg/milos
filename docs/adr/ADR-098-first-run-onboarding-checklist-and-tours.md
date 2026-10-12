# ADR-098: First-run Onboarding Checklist and Product Tours
Date: 2026-10-12
Status: Accepted (amended by ADR-100: tour completion is stored per account)

## Context
New tenant admins landed on an empty dashboard with no guidance about what to
configure, and clients had no introduction to the app.

## Decision
- A six-step admin checklist (app settings, classes, packages, first workout,
  invite clients, tour) modelled by the pure `OnboardingChecklist` domain
  module. Steps auto-complete from real data (class types, packages, workouts,
  clients or pending invitations); the admin can also mark done, skip, undo,
  dismiss the popup and restore it. Only those choices are persisted, under
  `organization_settings.settings["onboarding"]`, via
  `GET|PATCH /api/org/:slug/admin/onboarding`.
- The checklist appears as a warning-styled popup for owners/admins until it is
  finished or dismissed ("Remind me later" hides it for the session) and is
  always available at the top of Utility → App configuration.
- Role-specific product tours (admin 6 steps, member and athlete 5 steps) open
  on first visit, can be replayed from the profile page and the checklist,
  support keyboard navigation and render as a bottom sheet on phones. Copy is
  in all 12 locales and interpolates the real navigation labels.

## Rationale
Checklists of under seven items with visible progress, skip and resume, and
short skippable tours are the common pattern in onboarding guidance; auto
detection avoids asking admins to tick things they already did.

## Alternatives Considered
Per-admin persistence was rejected for the checklist: setup is an
organization concern shared by co-admins.

## Consequences
Tour completion for members and athletes is stored in the browser
(TD-050). Signals are recomputed on every checklist read, which loads the
tenant's workout list (acceptable for setup-sized tenants).

## Implementation Notes
Live-tested on desktop and a 390 px viewport; the popup footer was made sticky
on phones after testing.
