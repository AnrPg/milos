# Codex Brief — Workout Creation Canvas

> **You are implementing the Phase 2 hardening of the workout creation page.**
> Read this brief in full, then read the spec and plan files listed below before writing a single line of code.

---

## What You Are Building

The existing `/admin/workouts/new` page has a plain, single-column form that needs a complete UX overhaul. You are replacing it with a **3-panel canvas** — a professional-grade authoring environment where a trainer can compose workouts the way a musician composes a track: everything visible, everything draggable, everything live.

This is the most used admin tool in the app. It must feel fast, spacious, and satisfying.

---

## The Three Authoritative Documents

Read them all before touching code. They do not repeat each other.

| What | Path |
|---|---|
| **UX Design Spec** (frozen, approved) | `docs/superpowers/specs/2026-06-06-workout-creation-ux-design.md` |
| **Backend + Schema Plan** | `docs/superpowers/plans/2026-06-07-workout-creation-ux-backend.md` |
| **Frontend Plan (Part A)** | `docs/superpowers/plans/2026-06-07-workout-creation-ux-frontend-a.md` |
| **Frontend Plan (Part B)** | `docs/superpowers/plans/2026-06-07-workout-creation-ux-frontend-b.md` |
| **Overview + File Map** | `docs/superpowers/plans/2026-06-07-workout-creation-ux.md` |

The spec is the design bible. The plan files are step-by-step implementation guides with complete code for every task. **Follow them exactly.**

---

## The Vision, In Plain Language

### The Layout

Three panels side by side, full viewport height:

- **Left** — a list of section chips. Clicking a chip selects it and reveals its config below the list. Sections are drag-sortable. Each chip has a badge: ✓ (lime green) when the section is complete, ! (amber) when something is missing.

- **Middle** — always visible. Shows the exercises for whichever section is currently selected. Each exercise is a compact single-row card. Cards are drag-sortable within the section. Dragging a card over a section chip in the left panel moves it to that section.

- **Right** — a live preview that updates as the admin types and edits. It has tabs at the top: "Base" plus one tab per scale level that has at least one variation. Switching tabs re-renders all exercise values for that scale. This is what athletes will see.

Left and right panels can be collapsed to a thin strip to give the middle more room.

### The Save Model

There is no "Save" button. Everything is autosaved silently as the admin types, with a 1.5-second debounce. The header shows a status indicator: ↻ saving / ✓ saved / ⚠ failed. 

The only explicit action is **Publish** — a lime-green button that is disabled until the workout is complete (title, type, every section has a name and at least one valid exercise). Publish permanently makes the workout visible to members and athletes, then redirects to the workout list.

### The Dark Theme

The color palette is defined in the spec. Roughly: very dark purple-black background, slightly lighter dark panels, a purple-grey accent color for selections and active borders, and lime green for the primary CTA and completion checkmarks. Nothing light, nothing harsh.

---

## The Exercise Card

The most important component in the whole canvas. Each exercise occupies a single compact row by default:

```
⠿  [Exercise name]   3 sets · 10 reps · 80 kg   [Vars ▾]  [⋯]
```

- The drag handle (`⠿`) is always visible.
- The unit labels (`reps`, `kg`) are **clickable** — clicking them cycles to the next option (`reps → secs → kcal`, `kg → %RM`). This is called **unit cycling**. Only one unit is shown at a time; there are no dropdowns or segmented controls.
- For bodyweight exercises, the load area shows a dim `BW` badge instead of an input.
- `[Vars ▾]` opens the variations panel inline below the row.
- `[⋯]` opens the advanced settings panel inline below the row.

### Variations Panel

Shows one row per scale level that has a variation. Each row has:
- The scale level label
- An exercise name field — pre-filled with the base exercise name in muted grey; admin edits it to substitute a different exercise for that scale
- Sets / prescription value+unit / load value+unit — same unit cycling as the base row
- A `⊘` button pushed to the far right — clicking it excludes that exercise for athletes at that scale level

When a scale is excluded, its row shows "Excluded for this scale" with a ↩ Restore button.

The panel always has a `+ Add variation` button for any scale level that doesn't have a variation yet.

### Advanced Settings Panel

A set of toggleable settings. Key behavior: **the toggle track is the only thing that turns a setting on or off**. Clicking the label or the input field does NOT toggle. When a setting is off, its input fields are hidden (not greyed out — actually absent from the page). When on, the inputs appear.

Settings include: Heart Rate Zone, Tempo, Rest Between Sets, Cluster Sets Intra-Rest, Rest-Pause, Pacing.

At the bottom: a `✕ Remove exercise` link in red.

---

## The Format Dropdown

The section format (previously called "timer") is a **custom dropdown** — not a native `<select>`. It must support:
- Grouped options (18 formats across 6 groups: Basic, Interval, Sustained Cardio, Set-Based, Progressive, Rest)
- Per-option hover tooltips that appear to the right of the menu, showing what the format is best for, what it trains, how it works, and what the auto score type is

When a format is selected, **contextual fields** appear below the dropdown — number inputs with adjacent unit labels for the parameters specific to that format (e.g., AMRAP shows "Duration: [12] min"). These are never embedded inside the input value — always separate plain-text labels.

Some formats have an obvious score type (e.g., AMRAP always scores rounds+reps). For those, the score type is applied automatically and silently. The score type picker only appears for formats where the score is ambiguous.

---

## The New Save Flow (Backend Change)

This is the most important backend change. The current API creates a full validated workout in one shot. The new model is:

1. **Page loads** → immediately creates an empty draft record on the server (no title, no type, no sections yet) → gets back an ID
2. **Every 1.5 seconds** after any change → sends the full current state to the server as a draft update → server stores it as a raw blob, no validation
3. **Publish** → sends a publish request → server validates the full draft, creates the actual sections and exercises, marks status = published → frontend redirects

Drafts are invisible to members and athletes. The admin workout list shows drafts with a `[Draft]` badge. Published workouts can be re-opened (reverted to draft) for editing.

---

## Mobile

On screens narrower than 768px, the three panels are replaced by a sequential drill-down:
- View 1: sections list (with the header and a Preview button at the bottom)
- View 2: exercises for the selected section
- View 3: preview (slides up as a bottom sheet)

Cross-section exercise moves on mobile are done via a "Move to section" action in the advanced panel — not by dragging across panels.

---

## What NOT to Change

- Do not touch any code that is not related to workout creation. The scheduling, execution, gamification, coaching, and identity contexts are out of scope.
- Do not change the workout list page (`/admin/workouts`) except to show draft badges and link to edit existing drafts.
- Do not change the member/athlete-facing workout view.
- Do not change the scale levels management UI.
- Do not change the auth or session system.

---

## Architecture Rules (from AGENTS.md — non-negotiable)

- All writes go through Ecto changesets. No raw SQL mutations.
- Controllers call Application Services. Never the Repo directly.
- Domain modules are pure functions — no Ecto, no HTTP.
- Cross-context communication only through the context's public API.
- OpenAPI spec must be updated before adding a new endpoint.

---

## When to Stop and Ask

Stop and ask before proceeding if:
- A plan step requires a destructive DB operation not explicitly listed in the plan
- A TypeScript error cannot be resolved without changing the API contract
- The spec and plan contradict each other on a behavior
- A dependency listed in the plan is not installable or incompatible with the existing versions

---

## Definition of Done

- [ ] `mix test` passes with no failures or warnings
- [ ] `mix format` clean
- [ ] `mix credo --strict` clean
- [ ] `npx tsc --noEmit` passes
- [ ] `npm run build` succeeds
- [ ] The full flow works end-to-end: create draft → add sections → add exercises → add variations → preview syncs → publish → redirect to list
- [ ] Mobile layout renders correctly at 375px viewport width
- [ ] An ADR is written for the architecture decisions made during this implementation
