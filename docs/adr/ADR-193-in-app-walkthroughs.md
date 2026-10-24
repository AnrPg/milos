# ADR-193: In-app walkthroughs: one guide engine over real screens
Date: 2026-10-24
Status: Accepted

## Context
Staff need to learn three dense consoles: the shop (ADR-190/192), event organising (the 7-step wizard and the organiser console, ADR-185), and Finance › Offers (campaigns, coupons, partner perks, referrals, ADR-191). Members need to learn how to start their own club group and plan their own event, with a box as co-host or alone. ANR asked for walkthroughs that are interactive, very intuitive, insightful and simple, with few words. The vision doc already reserves «Βοήθεια & ξενάγηση: product tours» in Εγώ.

## Decision
- **One engine, many guides.** A guide is data (`apps/web/src/lib/guides/registry.ts`): steps with an optional route, an anchor, an action, a tip and visibility rules. One provider and one overlay in the root layout run at most one guide at a time.
- **Over the real screens, never a slideshow.** Each step dims the page with an SVG even-odd scrim and cuts a spotlight hole around the element it explains. Where a step says "tap", the person taps the real button. The guide moves on when the expected element appears (`until`) or disappears (`untilGone`). «Next» performs the same tap for them. A step that opens a dialog has a `leave` anchor (its close button), so a guide never leaves dialogs open behind it.
- **Anchors, not selectors.** Screens mark elements with `{...guideAnchor("shop.newProduct")}` (`data-guide`). The anchor registry adds fallbacks, for example a tab chip (`data-segment`) that falls back to its strip. A restyle or a translation cannot break a guide. A test checks that every anchor a guide uses is marked somewhere in the source.
- **Real labels in the copy.** A step can quote the real UI label (`{label}` filled from the screen's own message key), so the card and the button always say the same thing in all 12 locales.
- **Fits who is looking.** Steps have `requires`/`unless` rules on abilities (staff, manager, demo, hosts events, in a gym club). A missing anchor either centres the card with a "not here" note or skips the step. Demo businesses (ADR-184) get a «fill with demo data» button on the card.
- **Layout.** On phones the card is a sheet on the edge away from the spot. On wider screens it floats beside the spot. It uses theme variables only (`--scrim`, surface tokens) and a new layer `--z-tour: 85`, above dialogs, so it can explain them.
- **Progress belongs to the account.** `GET/PUT/DELETE /api/me/guides[/:id]` stores status (started/completed/dismissed), the step, the guide version and the number of runs in `guide_progress` (owner-only RLS, migration `20261220000000`). This keeps state the same across devices. Raising a guide's `version` offers it again. The current run (guide and step) is kept in sessionStorage, so it survives the navigations a guide makes and reloads.
- **Entry points, least clutter.** The `/guides` list (Εγώ › «Οδηγοί») shows each guide's state and a Start/Resume/Replay button. On a guide's home the guide is offered once, as a small card with «Not now». A «▶ Ξενάγηση» button sits in the header of the shop, organiser and finance consoles.
- **API shape (hexagonal).** The `Palee.Guides` context holds pure rules (`Domain.Progress`), a store port with a locked read-modify-write `update/4`, an Ecto adapter, an application service that emits `[:palee, :guides, :progress]` telemetry, and an OpenApiSpex controller. Limits: id `^[a-z][a-z0-9_]{1,47}$`, at most 100 guides per person, step ≤ 99, version ≤ 1000.

## Rationale
Pointing at the real UI teaches where things are, which screenshots or videos cannot do, and it stays correct as screens change. Driving by anchors and "until" conditions makes guides resilient to slow loads, empty states and layout differences. Guides as data mean that a new guide needs no engine change.

## Alternatives Considered
- **Third-party tour libraries** (Shepherd, Driver.js, react-joyride): they do not know our dialogs, z-scale, RTL, theme variables or Next routing, and they store progress only in the browser. Rejected.
- **Static explainer pages or videos:** cheaper, but not interactive, they go stale, and they need translating by hand. Rejected.
- **Progress in localStorage only:** this loses state across devices and re-offers guides after sign-in on a new phone. Rejected in favour of the account table.

## Consequences
- Screens that a guide points at carry `data-guide` anchors. Shared components (Dialog, SidePanel, Sheet, HubCard, StaffPanel, SegmentPicker, Card) accept a `guide` prop.
- Guide copy lives in the `Guides` namespace of every locale. Tests check that each step's keys exist everywhere.
- Fixed on the way: the shop console's Till button showed a raw message object (`t("pos")` → `t("pos.title")`).

## Implementation Notes
- To add a guide: add an id to `GuideId`, steps to `GUIDES`, copy under `Guides.<id>` in all locales, and anchors on the screens. The unit tests flag missing keys or anchors.
- e2e: `apps/web/e2e/guides.spec.ts` walks the shop guide tap by tap and checks the one-time offer, Escape and the phone sheet.
