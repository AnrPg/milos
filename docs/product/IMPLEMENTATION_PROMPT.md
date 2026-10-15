# Kickoff prompt: implementing the Milos product vision

## Setup before starting the agent
1. **Branch:** work on `redesign/social-centered`, which is cut from `main` after PRs #2 and #3. The pre-redesign product is frozen as release **`v1.0.0`**, and the redesign will ship as **`v2.0.0`**. Each roadmap phase gets its own short-lived branch off `redesign/social-centered` (for example `redesign/p1-<milestone>`), merged back through PRs.
   **Naming:** the roadmap phases "v1/v2/v3" in the brief are *phases of the redesign*, not release versions. In plans and commits call them **Phase 1/2/3** so they are not confused with the tags.
2. **Mode:** start the session in **Plan mode** (`Shift+Tab` in Claude Code, or `permission_mode: plan`). The agent must not edit code until you approve the plan.
3. **Model and effort:** use the strongest model at high effort for planning. Execution can run at normal effort.
4. **CLAUDE.md:** add a pointer so every future session loads the brief:
   ```
   ## Product direction
   Member-app work must follow docs/product/2026-10-15-milos-product-vision-and-ia.md (source of truth)
   and docs/product/mockups/milos-ia-mockup.html. milos-bottom-bar-exploration.html is SUPERSEDED.
   ```
   Note: the current `.claude/CLAUDE.md` mandates the `vexp` MCP (`run_pipeline`). Make sure that server is connected in the session, or relax that rule. Otherwise the agent will be blocked from searching.
5. **Fast checks:** make sure the agent can run the repo's lint, typecheck and test commands (web: Next.js/TS; api: Elixir/mix). If cloud sessions are used, add a SessionStart hook that installs dependencies.
6. **Context hygiene:** one phase per session, and `/clear` between phases. The plan file on disk carries state forward, not the chat.

---

## The prompt (copy-paste)

```
You are the lead engineer implementing a product re-architecture of Milos (Next.js PWA in apps/web, Elixir/Phoenix API in apps/api).

SOURCE OF TRUTH — read fully before anything else:
- docs/product/2026-10-15-milos-product-vision-and-ia.md  (business + engineering brief; its §4 principles are non-negotiable)
- docs/product/mockups/milos-ia-mockup.html  (final clickable design; screenshots in docs/product/mockups/screens/)
- docs/product/mockups/README.md
IGNORE as a spec: docs/product/mockups/milos-bottom-bar-exploration.html (superseded, reasoning only).

BRANCH & VERSIONS: work on branch redesign/social-centered (baseline = release tag v1.0.0; the redesign ships as v2.0.0). The brief's roadmap "v1/v2/v3" = Phase 1/2/3 of the redesign — use the Phase names in plans/commits to avoid confusion with release tags. Ignore other redesign/* branches unless I mention them.

WORK IN PHASES, the brief's roadmap: Phase 1 → 2 → 3. We start with Phase 1 ONLY. Do not build Phase 2/3 features, but do not paint us into a corner (e.g. the visibility enum and Club entity should allow later kinds).

STEP 1 — EXPLORE (read-only, no edits):
- Map the current member navigation (apps/web/src/lib/role-navigation.ts), landing page, journal, my-workouts, schedule, execution flow, and the relevant API controllers/contexts/schemas.
- Verify every claim in the brief's §8.1 "existing feature → new home" table against the code; list mismatches.
- Note conventions: i18n (apps/web/src/i18n), design tokens (globals.css), ADRs in docs/adr, tests, offline outbox, realtime sync.

STEP 2 — ASK ME (interactive): before writing the plan, use the AskUserQuestion tool for every decision that is genuinely mine. Batch related questions (max 4 per round), give a recommended option first with trade-offs, and keep asking until nothing material is ambiguous. Examples of decisions to raise: route structure/URLs for the 4 tabs; whether old routes redirect; data model for Club/Channel/Post (new context vs extend messaging); how #wod-σήμερα leaderboard reuses existing leaderboard/challenges; visibility enum storage and migration of existing notes/reviews; feature flags/rollout per organization; staff/coach view of the new tabs; what is explicitly out of scope for Phase 1. Do NOT ask things you can answer from the code or the brief.

STEP 3 — PLAN: write docs/plans/redesign-phase-1-member-app.md containing:
- Goal, scope, explicit non-goals (Phase 2/3 items listed).
- Architecture decisions (as ADR candidates for docs/adr), data model + migrations, API endpoints (new/changed), web routes/components, i18n keys.
- Milestones as small, independently shippable PR-sized slices, in order, each with: files touched, acceptance criteria (tied to brief sections and mockup screens), tests to add, risks, and how to verify manually.
- A feature-coverage checklist proving no existing member feature loses its access point (brief §8.1 / mockup "Κάλυψη").
- Open questions remaining.
Then STOP and present the plan for approval. Do not write code yet.

STEP 4 — EXECUTE (only after I approve), one milestone at a time:
- Write/adjust tests first where practical; then implement; then run lint, typecheck and the relevant test suites until green.
- Follow principles: stable screens, one home per object, ⊕ only for posts, private by default, Club ≠ Box, i18n for all copy, existing design tokens.
- Keep the existing workout execution screen unchanged; Box "Έναρξη" just links to it.
- After each milestone: summarize what changed, show test results, update the plan file's checklist, commit with a clear message, and ask before starting the next milestone if any new decision appeared.
- If reality contradicts the brief, stop and ask; never silently diverge.

Start with STEP 1.
```

---

## Prompts for later phases
- **Phase 2:** same prompt, replace "Phase 1 ONLY" with "Phase 2 (brief §9, v2 row); Phase 1 is merged; read docs/plans/redesign-phase-1-member-app.md for what exists". Key decisions to surface: open clubs/events and trial-slot policy, `Γύρω μου` geo-search (PostGIS?), rotating check-in QR + Wallet passes, Body/Wellness data, photo storage and GDPR, Garmin integration, cross-org journal read model.
- **Phase 3:** Partners, seasons, WOD goals + anatomy atlas (reuse `exercise_catalog_entries.muscle_groups`, injury-risk regions), analytics, native wrapper, AI coach assistant.

## Why it's structured this way
- **Explore → plan → code → commit**, with planning in plan mode, is Anthropic's recommended workflow for large changes. It stops the agent from coding before it understands the code.
- **Interactive questioning** with `AskUserQuestion` gets your decisions up front, so they don't turn into silent assumptions.
- **A plan file on disk plus small milestones** keeps context small across sessions and makes every PR reviewable.
- **Tests and checks after every milestone** let the agent verify its own work, which is the biggest single quality lever.
