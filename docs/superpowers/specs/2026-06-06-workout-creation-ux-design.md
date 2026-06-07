# Workout Creation UX — Design Spec
**Date:** 2026-06-06  
**Updated:** 2026-06-07  
**Status:** Final — approved, ready for implementation plan  
**Scope:** `/admin/workouts/new` (and edit mode) — full redesign of the workout creation page  
**Context:** Phase 2 hardening. Phases 0–2 implemented by Codex. Frontend-first: design is frozen before any code is touched.

---

## Design Principles

- Minimal, colorful, uncluttered — progressive disclosure everywhere
- Mobile-first; desktop is an expanded version of the same model
- No aggressive validation upfront — fields enter error state only after blur-while-empty or on Publish attempt
- Order of all entities (sections, exercises) is determined by position in the list — no explicit order field; drag to reorder

**Tech stack:**  
Next.js 15 · Tailwind CSS · shadcn/ui · React Hook Form + Zod · dnd-kit (touch-enabled drag) · Zustand · TanStack Query

---

## Color Palette

| Token | Value | Purpose |
|---|---|---|
| `--bg` | `#0A0A0F` | Page background |
| `--panel` | `#221F29` | Left / right panel backgrounds |
| `--card` | `#1c1926` | Exercise cards |
| `--accent` | `#9c799c` | Selections, active borders, toggles, focus rings |
| `--lime` | `#C6FF2E` | Primary CTA (Publish), active tabs, completion badges |
| `--red` | `#FF4D6D` | Destructive actions, error states |
| `--amber` | `#FFB547` | Incomplete / warning states |
| `--text` | `#F0EDF8` | Primary text |
| `--muted` | `#8B82A7` | Secondary text, unit labels, hints |
| `--dim` | `#4A4460` | Drag handles, disabled, placeholders |

## Typography

- Workout title: `18px / 800`
- Section title in middle panel: `22px / 800`
- Exercise name: `16px / 700`
- Section chip name: `15px / 600`
- Field labels: `10px / 700 / uppercase / letter-spacing`
- Meta strips (format · params): `11px / 600 / uppercase`
- Unit labels (next to inputs): `14px / 500 / --muted`

## Shape

Border radius: `16px` (cards) · `20px` (chips/pills) · `30px` (header-level buttons)  
Inputs: chunky, generous padding, no sharp corners.

---

## Layout — 3-Panel Canvas

No entry modal. Admin lands directly on the canvas.

```
┌────────────────────────────────────────────────────────────────────────┐
│  ✦  [ Workout title ]  [ Type ▼ ]        N of M sections complete  ✓ Draft saved  [Publish ↗] │
├──────────────────┬──────────────────────────────────┬──────────────────┤
│  LEFT PANEL      │  MIDDLE PANEL (always visible)  │  RIGHT PANEL     │
│  collapsible     │  Exercises for selected section  │  collapsible     │
│  Sections list   │                                  │  Full preview    │
│  + Section config│                                  │  (all sections)  │
└──────────────────┴──────────────────────────────────┴──────────────────┘
```

All three panels share the full viewport height. Left and right collapse to a ~40px strip with a rotated label and expand arrow.

### Header Bar

Fixed, always visible. Contains:
- **Title**: inline-editable input, required
- **Type**: required — e.g. CrossFit, Strength, Gymnastics, Aerobics, Recovery (exact list from backend enum)
- **Completion summary**: plain text, e.g. `"1 of 3 sections complete"` — not dots or icons
- **Save status**: icon + text, e.g. `"✓ Draft saved"` or `"↻ Saving…"` or `"⚠ Draft not saved"` — see Save Flow
- **Publish button**: lime, `"Publish ↗"`, disabled while any required field is invalid; when disabled and hovered shows tooltip listing what is missing

---

## Left Panel — Sections

### Section List

Each section is represented as a chip. Chips are drag-sortable. The chip contains:
- Drag handle (`⠿`) — visible always or on hover, activates drag on pointer-down
- A dot or visual indicator for selected state
- Section name
- Completion badge: `✓` (lime) when all required fields are complete; `!` (amber) when any required field is missing or invalid. No intermediate partial state.

`[+]` button adds a new section.

### Section Config

Shown **below the section list**, but only while a section is actively selected. Clicking outside the left panel (or onto the middle/right panel) hides it — state is preserved, not reset. Re-selecting the section restores it. During drag, config is hidden to give more room to the list.

**Fields:**
- **Name** — required text input
- **Format** — required, custom dropdown (see Format section)
- **Contextual format fields** — change based on selected format (see Format section)
- **Scoreable** toggle — when off, all scoring UI is hidden entirely (not greyed — fully removed from DOM)
- **Score type** — only shown when the selected format does not have a clear automatic score type mapping; when automatic, the score type is silently pre-applied without exposing a field

---

## Format Field

Renamed from "Timer" — "Format" describes the structure, goal, and timing model of a section. "Timer" only describes a subset.

### Dropdown

A custom dropdown component (not a native `<select>`) is required to support option grouping and hover tooltips. Collapsed state shows the selected format name and a `▾` chevron. Expanded state shows a grouped list where each option displays the format name on the left and the auto-inferred score type (muted) on the right.

**Hover tooltip**: hovering any format option shows a floating info panel positioned to the right of the menu. Content template:
```
[Format name]
📌 Best for   — use cases / target audience
💪 Trains     — what it develops
⚙️ How        — execution description
🏆 Score      — auto score type, if applicable
```
Tooltip is non-interactive (`pointer-events: none`) and disappears on mouse-leave.

### Contextual Fields

When a format is selected, a group of fields appears below the dropdown. Each field uses a **number-only input** with a **separate unit label** beside it — units are never embedded inside the field value. Real default values are pre-filled; no placeholder-only fields.

Example — AMRAP:
```
Duration:  [ 12 ]  min
```

Example — Tabata:
```
Work:    [ 20 ]  secs
Rest:    [ 10 ]  secs
Rounds:  [  8 ]
```

Optional fields are labeled with a muted italic "— optional" note beside the label.

### Format List

Grouped as they appear in the dropdown:

#### Basic
| Format | Contextual Fields | Auto Score |
|---|---|---|
| `untimed` | — | manual |
| `for_time` | Time Cap (optional) | `time` |
| `train_to_exhaustion` | Rest between sets | `reps` |
| `kcal_target` | Target kcal, Time Cap (optional) | `kcal` |

#### Interval
| Format | Contextual Fields | Auto Score |
|---|---|---|
| `emom` | Total Duration, Interval | manual |
| `complex_emom` | Total Duration, Interval | manual |
| `even_odd` | Total Duration | manual |
| `billat` | Work Interval, Rest Interval, Cycles | manual |

#### Sustained Cardio
| Format | Contextual Fields | Auto Score |
|---|---|---|
| `amrap` | Duration | `rounds+reps` |
| `edt` | Duration, PR Zone Rounds (optional) | `reps` |
| `death_by` | Starting Reps, Added per Round | `reps` |

#### Set-Based
| Format | Contextual Fields | Auto Score |
|---|---|---|
| `tabata` | Work, Rest, Rounds | manual |
| `custom_hiit` | Work, Rest, Rounds | manual |
| `cluster` | Intra-set Rest, Sets | manual |
| `hrr` | Effort Duration, Target HR Zone (optional) | `hr_drop` |

#### Progressive
| Format | Contextual Fields | Auto Score |
|---|---|---|
| `ladder_ascending` | Start Reps, Step, Cap (optional) | manual |
| `ladder_descending` | Start Reps, Step, Min Reps | `time` |
| `pyramid` | Peak Reps, Step | `time` |

#### Rest
| Format | Contextual Fields | Auto Score |
|---|---|---|
| `rest` | Duration | — (not scoreable) |

### Score Types
```
time · reps · weight · rounds · rounds+reps · kcal · hr_drop · load
```

Score type is auto-applied when the format has a clear mapping. The score type field is only shown to the admin when the mapping is ambiguous and manual selection is needed.

---

## Middle Panel — Exercises

Shows exercises for the currently selected section only. The middle panel is always visible — it does not collapse.

### Exercise Card

Each exercise is a card. The default state is a single compact row. Additional panels expand below the row as needed.

**Base row (always visible, one line):**
```
⠿  [Exercise name]   N sets · [value] unit · [value] unit   [Vars ▾]  [⋯]
```

Where "unit" is a clickable plain-text label that cycles to the next option on click. Only one unit is shown at a time — not a segmented control or dropdown showing all options. Units cycle silently.

- **Prescription unit** cycles: `reps` → `secs` → `kcal` → `reps`
- **Load unit** cycles: `kg` → `%RM` → `kg` (or `lbs` → `%RM` → `lbs` based on user's metric config)
- The metric unit (kg vs lbs) is inferred from user settings — never presented as a picker
- When an exercise has no external load (e.g. bodyweight), the load field shows `BW` as a dim indicator

The drag handle (`⠿`) is always visible and activates drag on pointer-down.

### Variations Panel

Expanded by the `[Vars ▾]` button. The button label changes to `[Vars ▲]` when open. The panel appears inline below the base row.

Panel header: uppercase muted label `SCALE VARIATIONS` + a `+ Add variation` button that is always present when the panel is open.

Each scale level has one row. A variation row contains:
- Scale label (emoji + name, fixed width)
- Exercise name override — editable text field, pre-filled with the base exercise name, shown in muted grey; editing it substitutes a different exercise for this scale level
- Numeric inputs for sets, prescription value, and load — using the same unit cycling as the base row
- An `⊘` exclude button pushed to the far right — subtle (transparent background, dim color, hover → red); excluding a scale removes that exercise for athletes at that level

When a scale is excluded, its row changes to show a dim "Excluded for this scale" label and a `↩ Restore` button.

### Advanced Settings Panel

Expanded by the `[⋯]` button. Appears inline below the exercise row (same pattern as the variations panel). The `[⋯]` button indicates it is open via a visual state change (e.g. accent border).

Panel header: `ADVANCED SETTINGS` label + `✕ Close` link.

For exercises inside a superset: a `⧉ Remove from superset` action link appears at the top.

Each advanced setting has its own toggle. The toggle is the **only element** that enables or disables the setting — clicking elsewhere in the row (label, input) does not affect the toggle. When a toggle is **off**, the corresponding input(s) are **hidden**. When **on**, the input(s) appear beside the label.

This means:
- The panel shows all setting labels (always)
- Input fields only appear next to settings that are enabled

Input fields contain numbers only; the unit is a separate label beside the input (not inside). Real default values are pre-filled.

Available advanced settings (non-exhaustive — implementation may add more):

| Setting | Input | Unit |
|---|---|---|
| Heart Rate Zone | zone number | Zone |
| Tempo | four numbers (ecc – pause – con – top) | — |
| Rest Between Sets | duration | secs |
| Cluster Sets intra-rest | duration | secs |
| Rest-Pause | duration | secs |
| Pacing | value | per-distance unit (e.g. /km) |

A `✕ Remove exercise` destructive button appears at the bottom of the panel.

### Supersets

Activated via the `⧉ Add to superset` action in the advanced settings panel. A superset groups consecutive exercises visually into a bordered wrapper with an accent-colored border and a `SUPERSET` label at the top.

The wrapper uses `overflow: visible` so that variations and advanced panels from exercises inside it can render outside the group boundary. Exercises inside share the group border and have no individual card border.

Removing an exercise from a superset uses the `⧉ Remove from superset` link in its advanced panel.

Example:
```
╔══ SUPERSET ════════════════════════════════════════════════════╗
║ ⠿  Pull-ups   3 sets · 10 reps · BW      [Vars ▾]  [⋯]       ║
║ ⠿  Dips       3 sets · 12 reps · BW      [Vars ▾]  [⋯]       ║
╚════════════════════════════════════════════════════════════════╝
```

### Format-Specific Exercise Behavior

When a section uses `complex_emom`, each exercise card gains a minute-assignment indicator (e.g. `Min 1`, `Min 2`). When a section uses `even_odd`, exercises get an `Even / Odd` toggle instead. Exercises without an assignment show a warning indicator (non-blocking).

### Required Fields — Exercise Level

Name, sets, prescription (value + unit), and load (value + mode) are required. All advanced settings are optional. Validation shows only after the field has been touched and left empty, or after a Publish attempt.

### Empty States

No section selected: prompt to select or add a section.  
Section selected, no exercises: prompt to add the first exercise.

---

## Right Panel — Preview

Collapsible drawer. Collapsed state: narrow strip with rotated `PREVIEW` label and expand arrow.

Shows the full workout — all sections, all exercises — updated live as edits are made. Reflects section reordering, exercise reordering, prescription changes, format changes, and scale variations.

**Scale tabs** at the top of the panel: Base is always present; additional tabs appear for each defined scale level. Switching tabs re-renders all exercise values using the variation for that scale — exercises with no variation for the active tab show their base values with a dim `(base)` label. Exercises excluded for the active scale are shown crossed out or dimmed.

Sections in the preview are collapsible (collapse in preview only — does not affect canvas state). Sections with no exercises show a warning indicator.

Advanced settings (HR Zone, Tempo, Pacing, etc.) are **not shown** in preview — the preview is athlete-facing and must remain minimal.

Format is shown as a human-readable summary, for example: `AMRAP 12 min`, `Tabata · 20/10 · 8 rounds`.

Varied exercise values are highlighted (e.g. lime color) to make it easy to spot differences between scales. Base values are shown in a muted style.

---

## Mobile Layout — < 768px

Progressive drill-down: three views navigated sequentially rather than shown side-by-side.

**View 1 — Sections list:**  
Fixed header with title, type, completion summary, and Publish button. Section chips with drag handles (long-press to activate). Bottom bar with `[Preview]` button.

**View 2 — Exercises for a section:**  
Back navigation to sections view. Section name and format as subheader. `[Edit format]` opens section config as a bottom sheet. Exercise list with drag handles. Bottom bar with `[Preview]`.

**Preview:**  
Bottom sheet, slides up. Same scale tabs and content as the desktop right panel. Dismissed by swipe-down or close button.

Mobile-specific behavior:
- Cross-section exercise moves handled via ⋯ advanced panel action rather than drag
- Section config is a bottom sheet, not an inline left-panel section
- Completion summary appears as text in the header (same as desktop)
- Drag reorder uses dnd-kit's touch sensor

---

## Save Flow

### Autosave (draft)

Every change triggers a debounced save (1.5 s) via `PATCH /api/admin/workouts/:id/draft`. No validation — incomplete drafts are saved as-is. A draft record is auto-created on page mount (`POST /api/admin/workouts`) to obtain an ID before the admin has filled anything in.

Header status indicator cycles through: `↻ Saving…` → `✓ Draft saved` → `⚠ Draft not saved — retrying` (on network error, with exponential backoff).

### Publish

The `Publish ↗` button is a hard gate. It is disabled until all required fields across all sections and exercises are valid. When disabled and hovered, a tooltip lists specifically what is missing (e.g. `"Section 'Cool-down': no exercises"`).

On click: `POST /api/admin/workouts/:id/publish`. Success → redirect to `/admin/workouts` with a toast. Failure → inline error, stay on page.

### Draft Visibility

Drafts appear in the admin workout list with a `[Draft]` badge. Members and athletes never see drafts. Admin can re-open a draft to resume editing. Published workouts can be unpublished (reverted to draft) for editing.

---

## Drag and Drop

**Library**: `dnd-kit` — chosen for built-in touch sensor support (required for mobile).

**Exercise reorder within a section**: `SortableContext` + `useSortable` per exercise card. Drag handle is the only activation point. A placeholder appears at the insertion point during drag.

**Section reorder**: Same pattern in the left panel section list.

**Cross-section exercise move (desktop)**: Dragging an exercise over a section chip in the left panel highlights that chip as a drop target. After ~300 ms hover delay, the middle panel switches to show that section. A ghost placeholder appears. On drop, the exercise moves to that position. Implemented via `DragOverlay` + `onDragOver`.

**Cross-section exercise move (mobile)**: Via a "Move to section →" action in the advanced settings panel — no cross-panel drag on mobile.

**All panels are independently scrollable**: left panel body, middle exercise list, right panel preview each have their own `overflow-y: auto` scroll container.

---

## Backend API Contract

### Endpoints

```
POST   /api/admin/workouts              → create draft, returns { id }
PATCH  /api/admin/workouts/:id/draft   → autosave (no validation)
POST   /api/admin/workouts/:id/publish → validate + publish
GET    /api/admin/workouts/:id         → load existing for edit
```

### workout_sections — `timer_config` JSONB

Stores all format-specific parameters. Key fields (not exhaustive — extend as formats are added):

```json
{
  "type": "amrap",
  "duration_seconds": 720,
  "time_cap_seconds": null,
  "interval_seconds": 60,
  "rounds": 8,
  "work_seconds": 20,
  "rest_seconds": 10,
  "ladder_start": 1,
  "ladder_step": 1,
  "ladder_cap": 10,
  "hr_threshold_bpm": null,
  "hr_threshold_pct": null
}
```

### workout_exercises — extended fields

```json
{
  "name": "Back Squat",
  "order": 1,
  "sets": 5,
  "prescription_value": 5,
  "prescription_unit": "reps",
  "load_value": 80,
  "load_mode": "absolute",
  "superset_group_id": null,
  "hr_zone": null,
  "tempo": null,
  "rest_seconds": null,
  "cluster_rest_seconds": null,
  "rest_pause_seconds": null,
  "pacing": null,
  "interval_assignment": null
}
```

Notes:
- `load_mode`: `"absolute"` or `"pct_1rm"` — no `load_lbs` field; display unit (kg/lbs) is resolved at render time from user metric settings
- `prescription_unit`: `"reps"`, `"secs"`, or `"kcal"`
- `interval_assignment`: integer (which minute this exercise belongs to, for `complex_emom` / `even_odd`)

### workout_exercise_variations

```json
{
  "exercise_id": "uuid",
  "scale_level": "beginner",
  "exercise_name_override": null,
  "sets": 3,
  "prescription_value": 5,
  "prescription_unit": "reps",
  "load_value": 60,
  "load_mode": "absolute",
  "excluded": false
}
```

### Status field on workouts

`status`: `:draft | :published`. Draft workouts are filtered out of all member/athlete-facing queries.

---

## All Design Decisions — Final

- Layout: 3-panel canvas (left collapsible + middle fixed + right collapsible)
- Color palette: `#0A0A0F` bg · `#221F29` panel · `#9c799c` accent · `#C6FF2E` lime CTA
- Header completion: plain text `"N of M sections complete"` — not dots or icons
- Section badges: `✓` lime (complete) / `!` amber (incomplete) only — no partial state
- Section config: shown only when a section is selected; auto-hides on click-away
- Format: renamed from "Timer"; custom dropdown with grouped options and per-option hover tooltips
- Contextual format fields: number inputs + adjacent unit labels; real default values; no units inside field values
- Score type: only shown when ambiguous; auto-inferred and silently applied when clear
- Exercise card: single-line base row; unit cycling (one unit visible at a time, click to cycle)
- Prescription: `reps → secs → kcal` cycle
- Load: `kg → %RM` cycle (or `lbs → %RM`); BW shown as dim indicator for bodyweight exercises
- Variations panel: inline below exercise row; exercise name override editable in grey; unit cycling same as base; ⊘ exclude pushes far right
- Advanced settings panel: inline below exercise (same pattern as variations); labels always visible; input fields visible only when that setting's toggle is ON, hidden when OFF; toggle is the only click target that changes enabled state
- Supersets: border-wrapped group; overflow:visible; no individual card borders inside group
- Preview panel: data-driven; synced to scale tab; varied values highlighted; base values dimmed; advanced fields not shown
- Save flow: autosave draft on every change (debounced) + explicit Publish hard gate → redirect to /admin/workouts
- Mobile: progressive drill-down; cross-section moves via action (not drag); section config as bottom sheet
- Drag and drop: dnd-kit; within-section and cross-section (desktop); section list; long-press on mobile
- Unit label wording: `secs` (not `s`)
