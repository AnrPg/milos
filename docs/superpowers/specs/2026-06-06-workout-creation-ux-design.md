# Workout Creation UX — Design Log
**Date:** 2026-06-06  
**Updated:** 2026-06-07  
**Status:** Final — approved by user, ready for implementation plan
**Scope:** `/admin/workouts/new` — full redesign of the workout creation page (Phase 2 hardening, frontend-first)
**Context:** Phases 0–2 implemented by Codex. Phase 2 (`WorkoutForm.tsx`, `WorkoutAdminConsole.tsx`) needs UX hardening. Design is decided before any code is touched.

---

## Design Principles

- Minimal, colorful, uncluttered, simplistic
- Mobile-first, progressive disclosure
- Tech: Next.js 15 · Tailwind CSS · shadcn/ui · React Hook Form + Zod · dnd-kit (touch-enabled) · Zustand · TanStack Query

### Color Palette (finalized in wireframe session)
| Token | Value | Usage |
|---|---|---|
| `--bg` | `#0A0A0F` | Page background |
| `--panel` | `#221F29` | Left / right panel background, card backgrounds |
| `--card` | `#1c1926` | Exercise cards |
| `--accent` | `#9c799c` | Primary accent — selections, borders, toggles, focus rings |
| `--lime` | `#C6FF2E` | CTA (Publish button), active scale tabs, variation dot indicators, ✓ badges |
| `--red` | `#FF4D6D` | Destructive actions, error states |
| `--amber` | `#FFB547` | Warning / incomplete badges |
| `--text` | `#F0EDF8` | Primary text |
| `--muted` | `#8B82A7` | Secondary text, units, labels |
| `--dim` | `#4A4460` | Disabled / placeholder / drag handles |

### Typography Scale
- Workout title (header): `18px / 800`
- Section title (middle panel header): `22px / 800`
- Exercise name: `16px / 700`
- Section name (chip): `15px / 600`
- Section config labels: `10px / 700 / uppercase / letter-spacing`
- Meta strips (format · duration): `11px / 600 / uppercase`
- Unit labels: `14px / 500 / --muted`

### Shape
- Border radius: `16px` (cards) · `20px` (pills/chips) · `30px` (header elements, publish button)
- Chunky inputs with generous padding

---

## Layout Decision — 3-Panel Canvas

**Chosen approach: Proposal 2 — Inline Header Bar with 3 panels**

No entry modal. The admin lands directly on the canvas. All panels visible immediately.

```
┌───────────────────────────────────────────────────────────────────────────┐
│  ✦  [ Untitled workout__________________ ]  [ CrossFit ▼ ]   [ Save  ]  │  ← fixed header bar
├──────────────────┬───────────────────────────────┬────────────────────────┤
│  LEFT PANEL      │  MIDDLE PANEL                 │  RIGHT PANEL           │
│  (drawer)        │  (always visible, ~50% width) │  (drawer)              │
│  Sections list   │  Exercises of selected        │  Full workout preview  │
│  + Section config│  section only                 │  (all sections, live)  │
└──────────────────┴───────────────────────────────┴────────────────────────┘
```

### Header Bar (fixed, always visible)
- **Title**: inline-editable `<input>`, placeholder "Workout title", required
- **Type**: required — options: CrossFit · Strength · Gymnastics · Aerobics · Flexibility · Recovery
- **Save button**: disabled + greyed while any required field is incomplete. Hover → tooltip listing what is missing (e.g. "2 sections incomplete, 1 exercise missing prescription")
- **Completion indicator**: e.g. `● ● ○` — one dot per section, filled = complete

### Validation Philosophy
- No aggressive red upfront
- A field enters "invalid" state only on: (a) touched + empty on blur, OR (b) admin hits Save
- Required fields must be clearly indicated (subtle marker, not shouting)
- **Conditional required ("either-or")**: e.g. exercise reps OR duration_seconds — treated as one composite field; at least one must be filled. Both empty = invalid. One filled = valid.
- Order of entities: **not an explicit field** — determined by position in the UI list. Admin drags to reorder.

---

## Left Panel — Sections + Section Config

### Section List
- Each section chip has:
  - `⠿` drag handle (visible on hover only)
  - `●/○` selected / not-selected indicator
  - Completion badge: `✓` (all required fields filled) · `◐` (partially filled) · `!` (has invalid field after blur)
  - Click → selects section; middle panel switches to show that section's exercises
- `[+]` button at top-right adds a new section

### Section Config
- **Visibility**: shown below the section list **only when a section is actively selected** in the left panel
  - If admin clicks empty space in left panel → config disappears (state preserved)
  - If focus moves to another panel → config disappears (state preserved)
  - Re-selecting same section → config reappears in last state
  - During drag → config hidden (more room for list)
- **Fields**:
  - `Name` — text input, required, red ring on blur-while-empty
  - `Format` — custom dropdown (not native `<select>`), required — see Format section below
  - Contextual format fields — shown/hidden based on selected format
  - `Scoreable` toggle — when off, all score fields hidden entirely (not greyed, fully gone)
  - Score fields (revealed when Scoreable = true):
    - `Score type` — auto-pre-filled if format has clear mapping (shows `auto` badge, still editable); manual if ambiguous
    - `Label` · `Unit`

### Visual State Machine — Left Panel
```
[no section selected]   → section list only
[section selected]      → section list + config below
[drag in progress]      → section list only (config hidden for space)
```

---

## Format Field (renamed from "Timer")

**Rationale for rename**: "Timer" describes only a subset of the options. "Format" describes the structure, goal, and timing workflow of a section. Alternatives considered: "Structure", "Protocol" — "Format" chosen as most minimal and domain-appropriate.

### Custom Dropdown Component (finalized)
- Custom JS-driven dropdown (not native `<select>`) — required for grouped headers and per-option hover tooltips
- Collapsed state: button showing selected format name + `▾` chevron
- Expanded state: grouped list panel — format name on left, auto score type hint on right (muted)
- **Hover tooltip**: hovering any format option shows a floating panel to the **right of the menu** with:
  ```
  📌 Best for       — use cases
  💪 Trains         — what it develops
  ⚙️ How            — execution instructions
  🏆 Score          — auto score type (if applicable)
  ```
  Tooltip is `pointer-events: none`, disappears on mouseLeave
- Clicking an option: selects format, closes dropdown, updates contextual fields

### Contextual Format Fields (finalized)
Fields appear as a boxed group below the format dropdown. Each field:
- Label (`10px / uppercase / muted`)
- **Number-only input** (no units inside the field value)
- Unit label **next to** the input as a separate element
- Real default values filled in (no placeholders)
- Optional fields labeled with an italic "— optional" hint next to the label

Example (AMRAP):
```
Duration:  [ 12 ]  min
```
Example (Tabata):
```
Work:     [ 20 ]  secs
Rest:     [ 10 ]  secs
Rounds:   [  8 ]
```

---

## Full Format List

Grouped as they appear in the dropdown:

### Basic
| Format | Contextual Fields | Auto Score Type |
|---|---|---|
| `untimed` | — | manual |
| `for_time` | Optional: Time Cap | `time` |
| `train_to_exhaustion` | — | `reps` |
| `kcal_target` | Target kcal · Optional time cap | `kcal` |

### Interval
| Format | Contextual Fields | Auto Score Type |
|---|---|---|
| `every_x_mins` | Interval (min) · Rounds | manual |
| `complex_emom` | Interval (min) · Total minutes | manual |
| `otm_anti_glycolytic` | Interval secs · Work cap secs | manual |
| `even_odd` | Total minutes | manual |

### Sustained Cardio
| Format | Contextual Fields | Auto Score Type |
|---|---|---|
| `amrap` | Duration | `rounds+reps` |
| `intermittent_splits` | Work secs · Recovery secs · Total duration | `avg_bpm` |
| `edt` | Duration | `rounds` |
| `death_by` | Start reps · Increment · Interval secs | `reps` |

### Set-Based
| Format | Contextual Fields | Auto Score Type |
|---|---|---|
| `tabata` | Work secs · Rest secs · Rounds | manual |
| `custom_hiit` | Work secs · Rest secs · Rounds | manual |
| `fixed_duration` | Duration · Rounds | manual |
| `work_rest_ratio` | Work secs · Ratio (1:1 / 1:2 / 1:3) · Rounds | manual |

### Progressive
| Format | Contextual Fields | Auto Score Type |
|---|---|---|
| `ladder_ascending` | Start reps · End reps · Step · Rest (optional) | manual |
| `ladder_descending` | Start reps · End reps · Step · Rest (optional) | manual |
| `pyramid` | Peak reps · Step · Rest (optional) | manual |

### Rest
| Format | Contextual Fields | Auto Score Type |
|---|---|---|
| `rest` | Duration | — (not scoreable) |

### Biometric (v2)
| Format | Contextual Fields | Auto Score Type |
|---|---|---|
| `hrr_timer` | HR threshold (BPM or % max HR) · Manual fallback | manual |

**v1 HRR fallback**: no wearable SDK in v1. Format exists in UI but athlete uses "Ready" button when they feel threshold is reached.

---

## Auto Score Type Inference

When admin ticks "Scoreable":
- If format has a **clear auto-mapping** → score type pre-filled, shown with `[auto]` badge
  - Badge tooltip: "Detected from [Format] format. Change if needed."
  - Field remains editable
- If **ambiguous** → score type field shown as normal for manual selection

---

## Score Types (full list)
```
time · reps · weight · rounds · load · kcal · avg_bpm · peak_bpm · rounds+reps
```

---

## Middle Panel — Exercises

### Cross-Section Exercise Drag
- Exercise cards have a drag handle (`⠿`)
- Dragging an exercise out of the middle panel and **hovering over a section chip** in the left panel:
  - That section becomes highlighted as drop target
  - After ~300ms hover delay: that section opens in the middle panel
  - Ghost placeholder shown in the new section as admin hovers
  - On drop: exercise moves to that section at the dropped position

### Variation UX (finalized)
Each exercise card has a `[Vars ▾]` button. Clicking it expands an inline panel below the exercise row:
- Panel header: "SCALE VARIATIONS" label (dim uppercase) + `+ Add variation` button (always visible, lime accent)
- One row per scale level defined in the workout
- `[Vars ▲]` when open (chevron inverts)

**Variation row layout:**
```
[🟢 Beginner]  [exercise name, editable, grey]  [3] × [5] reps  [60] kg   ⊘
```
- **Scale label**: emoji + name (e.g. `🟢 Beginner`), `90px` fixed width
- **Exercise name override**: editable text input, value = base exercise name by default, shown in `--muted` grey (editable, focus → white); editing substitutes a different exercise for this scale
- **Number inputs**: sets, reps/secs/kcal, load — same cycling behavior as main exercise units
  - `reps` unit: click cycles `reps → secs → kcal`
  - `kg`/`lbs` unit: click cycles `kg → %RM` (or `lbs → %RM`)
- **⊘ Exclude button**: pushed far right via `margin-left: auto`, transparent background, `--dim` color, hover → `--red`, `title="Exclude for [scale] scale"` — removes exercise from this scale level

**Excluded scale:**
```
[🔴 Advanced]  [Excluded for this scale]                              ↩ Restore
```
- Shown in dim/italic, restore button at far right

### Exercise-Level Fields

**Prescription field — single numerical + cycling unit (finalized):**
```
[ 5 ]  reps   ← click "reps" to cycle → secs → kcal → reps
```
- One numerical input + plain-text clickable unit label
- Clicking the unit label cycles through: `reps` → `secs` → `kcal`
- Unit label styled as `--muted`, dashed underline on hover, accent color on hover
- Both number AND unit required — either empty = invalid

**Load field — required, cycling between kg (or lbs) and %RM (finalized):**
```
[ 80 ]  kg    ← click "kg" to cycle → %RM → kg
```
- Required. No bodyweight default — exercise explicitly marked BW (see below)
- Clicking unit cycles: `kg` ↔ `%RM` (or `lbs` ↔ `%RM` depending on user metric config)
- kg/lbs inferred from user metric config — never shown as a picker

**Bodyweight exercises:**
- When load is not applicable (e.g. pull-ups, dips), the load field shows `BW` (Bodyweight) as a dim text indicator with `title="Bodyweight — no external load"`
- Admin sets this via the load field — typing nothing and selecting a "BW" option, or via ⋯ advanced panel

**Base fields (one-line layout, always visible):**
```
⠿  [Exercise name___________]   5 sets · [5] reps · [80] kg   [Vars ▾]  [⋯]
```

**Advanced Settings Panel (finalized — replaces dropdown menu):**
- `⋯` button opens an **inline expandable panel** below the exercise row (same as variations panel)
- Panel header: "Advanced Settings" + "✕ Close" link
- **All fields always visible** — no show/hide on toggle
- Each row: `[toggle track] [label] [number input] [unit label]`
- Toggle track is the **only** clickable element to enable/disable a setting — clicking the row or input does NOT toggle
- Enabled row: label turns white, input border highlights in `--accent`
- Disabled row: label stays `--muted`, value still editable and saved (toggle just marks it active)
- For superset exercises only: "⧉ Remove from superset" action link at top of panel
- "✕ Remove exercise" destructive button at bottom

**Advanced fields:**
| Field | Input | Unit |
|---|---|---|
| Heart Rate Zone | `[3]` | Zone |
| Tempo (ecc–pause–con–top) | `[3]` `[1]` `[3]` `[0]` | — (four sequential number inputs) |
| Rest Between Sets | `[90]` | secs |
| Cluster Sets (intra-rest) | `[15]` | secs |
| Rest-Pause | `[10]` | secs |
| Pacing | `[5:30]` | /km |

### Exercise Card — Full Anatomy

**Default (base fields only):**
```
┌──────────────────────────────────────────────────────────────────┐
│ ⠿  Push-ups                              [ Variations → ]  [⋯] │
│     3 sets  ·  [ 10 ] [ reps | s | kcal ]  ·  [ 80 ] [ Abs | %1RM ] kg │
└──────────────────────────────────────────────────────────────────┘
```

**Expanded via [⋯]:**
```
┌──────────────────────────────────────────────────────────────────┐
│ ⠿  Push-ups                              [ Variations → ]  [⋯] │
│     3 sets  ·  [ 10 ] [ reps | s | kcal ]  ·  [ 80 ] [ Abs | %1RM ] kg │
│  ─────────────────────────────────────────────────────────────   │
│  HR Zone  [ Z2 ▼ ]      HR Rest  [ Z1 ▼ ]                       │
│  Tempo    [ 3-1-2-0__ ]  Pacing  [ _____ / 500m ▼ ]            │
│  □ Cluster sets    [__] reps · [__] s micro-rest                 │
│  □ Rest-pause      [__] s countdown after failure                │
│  □ Superset        group with next exercise ↓                    │
└──────────────────────────────────────────────────────────────────┘
```

### Supersets (finalized visual)
- Activated via "⧉ Add to superset" in the `⋯` advanced panel
- Visual: accent-colored **border wrapper** with rounded corners, `SUPERSET` label at the top in a tinted header strip
- The group wrapper uses `overflow: visible` — variations and advanced panels from exercises inside can render outside the group border
- Exercises inside: no individual card border, shared group border only
- Removing from superset: "⧉ Remove from superset" in that exercise's advanced panel
```
┌── SUPERSET ──────────────────────────────────────────────────┐
│ ⠿  Pull-ups      3 sets · 10 reps · BW        [Vars ▾] [⋯] │
│ ⠿  Dips          3 sets · 12 reps · BW         [Vars ▾] [⋯] │
└──────────────────────────────────────────────────────────────┘
```

### Section Badges (finalized)
- `✓` in lime: all required fields complete
- `!` in amber: required field missing or invalid (after touch/blur or save attempt)
- No intermediate `◐` partial state — only done or not-done

### Complex EMOM / Even-Odd — Exercise Interval Assignment
When section format is `complex_emom`, each exercise card gets a **"Minute" tag** (dropdown):
```
│ ⠿  Push-ups  [ Min 1 ▼ ]    [ Variations → ]  [⋯] │
│ ⠿  Squats    [ Min 2 ▼ ]    [ Variations → ]  [⋯] │
```
For `even_odd`: tag becomes `[ Even | Odd ]` toggle instead.
Exercises without an assigned interval show `⚠` warning badge (non-blocking, flagged only).

### Required Field Validation — Exercise Level
| Field | Required | Rule |
|---|---|---|
| Name | ✓ | Non-empty string |
| Sets | ✓ | Positive integer |
| Prescription (number + unit) | ✓ | Both number AND unit must be set |
| Load (number + mode) | ✓ | Both number AND mode (Absolute / % 1RM) must be set |
| HR Zone, Tempo, Pacing | ✗ | Optional (advanced) |
| Cluster, Rest-pause, Superset | ✗ | Optional (advanced) |

### Empty States
**No section selected:**
```
←  Select a section to edit its exercises
   Or add a new one in the left panel.
```
**Section selected, no exercises yet:**
```
[Section name] — [format]
No exercises yet.
[ + Add first exercise ]
```

---

## Right Panel — Preview

- Collapsible drawer (right side). Collapsed = ~40px strip with rotated "PREVIEW" label + expand icon.
- Shows the **full workout** — all sections, all exercises
- Updates **live** as admin makes changes in left or middle panel
- Reflects **reordering** of sections and exercises in real time (Framer Motion layout animation)
- Scale level toggle tabs at top: `Base` always first + only scales with ≥1 variation defined
- Active scale tab: exercise values render with variation applied; exercises without variation for that scale show base values + subtle "base" indicator
- Sections: all expanded by default; collapsible per section (collapse/expand in preview only — does not affect canvas)
- Format shown as human-readable summary (e.g. "AMRAP 12:00", "E2MOM · 5 rounds", "Tabata · 20s/10s · 8r")
- Advanced exercise fields (HR Zone, Tempo, Pacing) **not shown** in preview — preview is athlete-facing, minimal
- Supersets: same left-border bracket visual as middle panel
- Live update map:
  - Typing exercise name → preview updates character-by-character
  - Prescription / load change → instant
  - Section reorder → animated position swap
  - Exercise reorder → animated within section
  - Cross-section drag → animated disappear/appear
  - Scoreable toggle → badge appears/disappears
  - Format change → summary label updates
  - Scale tab change → all exercise values re-render
- Empty state: "Your workout will appear here as you build it. Start by adding a section →"

---

## Mobile Layout — < 768px

**Chosen: Progressive drill-down (Option B)**

### Navigation levels

**Level 1 — Sections list (default landing):**
- Fixed header: title input + type select + Save button (with completion badge)
- Sections list with drag handles (long-press to activate), completion badges
- Bottom action bar: `[👁 Preview]` + `[Save]`
- Tap a section chip → navigates to Level 2

**Level 2 — Exercises (selected section):**
- Back nav "← [Section name]" + Save always accessible in header
- Section name + format summary shown as subheader; `[Edit format]` button → opens bottom sheet with section config form
- Exercise list with drag handles (long-press)
- `[⋯]` per exercise → "Move to section →" submenu (replaces cross-section drag)
- Bottom: `[👁 Preview]`

**Preview — bottom sheet (slides up from bottom):**
- Drag handle at top, swipe-down or ✕ to dismiss
- Full workout preview with scale tabs (same as desktop)
- Triggered from `[👁 Preview]` button on either level

### Mobile-specific adjustments
- Cross-section drag replaced by: `[⋯]` → "Move to section →" → section name list
- Section config on mobile: bottom sheet (not inline left panel)
- Completion indicator: badge on Save button e.g. `Save (2/3)` or red dot if errors
- Drag reorder: long-press handle → touch drag (dnd-kit touch support)

---

## Backend Implications (flagged — require ADR update before implementation)

1. New format types require extension of `timer_config` JSONB in `workout_sections`:
   - New `type` enum values: `every_x_mins`, `complex_emom`, `otm_anti_glycolytic`, `even_odd`, `intermittent_splits`, `edt`, `death_by`, `work_rest_ratio`, `ladder_ascending`, `ladder_descending`, `pyramid`, `train_to_exhaustion`, `kcal_target`, `hrr_timer`
   - New fields: `time_cap_seconds`, `work_cap_seconds`, `interval_minutes`, `ladder_start`, `ladder_end`, `ladder_step`, `recovery_seconds`, `hr_threshold_bpm`, `hr_threshold_pct`, `work_rest_ratio`

2. New exercise-level fields require extension of `workout_exercises` JSONB or new columns:
   - `load_kg`, `load_lbs`, `load_pct_1rm`
   - `kcal_target`
   - `hr_zone_work`, `hr_zone_rest`
   - `tempo` (TUT, e.g. "3-1-2-0")
   - `pacing` (value + unit)
   - `cluster_reps`, `cluster_rest_seconds`
   - `rest_pause_seconds`
   - `superset_group_id`

3. New score types: `kcal`, `avg_bpm`, `peak_bpm` — extend score_config type enum

4. `complex_emom` / `even_odd` exercises need `interval_assignment` (integer) — which minute they belong to

5. `master_workouts` needs `status: :draft | :published` field (autosave draft pattern):
   - Draft workouts not visible to members/athletes — Workouts.Queries filter by `status = :published`
   - New endpoint: `PATCH /api/workouts/:id/draft` (autosave, no validation)
   - New endpoint: `POST /api/workouts/:id/publish` (validates + sets status = :published)
   - Draft record auto-created on mount of `/admin/workouts/new` (POST on page load)

6. Exercise load field revised: no `load_lbs` stored — unit inferred from user metric config:
   - Store: `load_value` (numeric) + `load_mode: :absolute | :pct_1rm`
   - Display unit (kg/lbs) resolved at render time from user settings

---

## Save Flow

**Pattern: Autosave draft + Explicit Publish**

### Autosave
- Debounced: 1.5s after last change → PATCH `/api/workouts/:id/draft`
- Saves regardless of validation (incomplete drafts are valid to store)
- Status indicator in header: `↻ Saving...` → `✓ Draft saved` → `⚠ Draft not saved — retrying`
- Network error: exponential backoff retry; user sees warning indicator
- On first load of `/admin/workouts/new`: draft record auto-created (POST on mount)

### Publish Button (Hard Gate)
- Button label: "Publish ↗"
- Disabled while any required field is invalid
- Hover when disabled: tooltip with bullet list of what's missing (e.g. "Section «Main Set»: Squat missing load")
- Click → POST `/api/workouts/:id/publish`
- Success → redirect `/admin/workouts` + toast "Hero WOD published"
- Failure → inline error, stay on page

### Header Bar States
```
Editing unsaved   →  ↻ Saving...    [Publish ↗] (disabled)
Draft saved, invalid →  ✓ Draft saved  [Publish ↗] (disabled, tooltip)
Draft saved, valid   →  ✓ Draft saved  [Publish ↗] (enabled)
Publishing        →  ↻ Publishing…  [Publish ↗] (disabled)
```

### Draft Visibility
- `/admin/workouts` list shows drafts with `[Draft]` badge
- Members/Athletes never see drafts
- Admin can click draft → resume editing in canvas
- Published workout can be reverted to draft for editing (unpublish action)

### After Publish
- Redirect → `/admin/workouts`
- Success toast: "«[title]» published" (3s, dismissable)

### Mobile Save
- Autosave same logic
- Status: small dot in header (🟡 saving / 🟢 saved / 🔴 error)
- "Publish" in bottom action bar; shake animation if tapped while invalid

---

## Drag and Drop — Implementation Notes

**Library**: `dnd-kit` (chosen for native touch support, required for mobile)

### Within a section (exercise reorder)
- `@dnd-kit/sortable` — `SortableContext` wrapping the exercise list
- `useSortable` hook per exercise card
- Drag handle: `⠿` icon, `cursor: grab`, activates on pointer-down
- Drop indicator: placeholder card at insertion point
- Animation: `CSS.Transform` from dnd-kit's `useSortable`

### Cross-section drag
- Desktop: drag exercise card out of middle panel → hover over section chip in left panel → 300ms delay → that section opens → ghost placeholder appears → drop moves exercise
- Mobile: `⋯` advanced panel → "Move to section →" → section name list (no drag across sections on mobile)
- Implementation: custom `DragOverlay` + `onDragOver` handler updates which section is "active drop target"

### Section reorder (left panel)
- `SortableContext` in left panel section list
- Long-press or drag on `⠿` handle
- Section config hidden during drag (more room)

### All panels scrollable
- Left panel body: `overflow-y: auto` in a flex-1 container (sections list + config scroll together)
- Middle panel exercise list: `overflow-y: auto; flex: 1`
- Right panel preview: `overflow-y: auto; flex: 1`

---

## Backend API Contract (required before implementation)

### Draft/Publish endpoints
```
POST   /api/admin/workouts                    → create draft, returns { id }
PATCH  /api/admin/workouts/:id/draft          → autosave (no validation)
POST   /api/admin/workouts/:id/publish        → validate + publish
GET    /api/admin/workouts/:id                → load existing workout for edit
```

### Data shape (workout_sections timer_config JSONB — extended)
```json
{
  "type": "amrap | for_time | emom | tabata | ...",
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

### Data shape (workout_exercises — extended)
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
  "hr_zone_work": null,
  "tempo": "3-1-3-0",
  "rest_seconds": 90,
  "cluster_rest_seconds": null,
  "rest_pause_seconds": null,
  "pacing": null,
  "interval_assignment": null
}
```

### Scale variation shape (workout_exercise_variations)
```json
{
  "exercise_id": "uuid",
  "scale_level": "beginner | intermediate | advanced",
  "exercise_name_override": null,
  "sets": 3,
  "prescription_value": 5,
  "prescription_unit": "reps",
  "load_value": 60,
  "load_mode": "absolute",
  "excluded": false
}
```

---

## All Design Decisions — Resolved

- [x] Layout: 3-panel canvas (left drawer + middle always-visible + right drawer)
- [x] Color palette: `#0A0A0F` bg, `#221F29` panel, `#9c799c` accent, `#C6FF2E` lime CTA
- [x] Format field: renamed from "Timer", custom dropdown with grouped options and hover tooltips
- [x] Contextual format fields: number inputs + separate unit labels, real default values
- [x] Exercise card: one-line layout, unit cycling (reps/secs/kcal, kg/%RM)
- [x] Prescription: single `[value] [unit▾]`, unit cycles by click
- [x] Load: single `[value] [unit▾]`, kg↔%RM by click; BW displayed as dim indicator
- [x] Variations panel: inline below exercise, always-visible "+ Add variation", ⊘ exclude
- [x] Advanced settings: inline panel (not dropdown), all fields always visible, toggle per-field
- [x] Section badges: ✓ lime / ! amber only (no partial state)
- [x] Section config: auto-hides on click-away, shown only when section selected
- [x] Supersets: border-wrapped group, overflow:visible for child panels
- [x] Preview: data-driven, synced to scale tab, lime for varied, "(base)" for unchanged
- [x] Save flow: autosave draft + Publish hard gate → redirect to /admin/workouts
- [x] Mobile: progressive drill-down, bottom sheet for preview and section config
- [x] Drag and drop: dnd-kit, within-section + cross-section (desktop), long-press on mobile
- [x] "secs" not "s" throughout
