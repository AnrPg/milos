# Design Decisions In Progress
> Αυτό το αρχείο καταγράφει verbatim αποφάσεις από τη συνομιλία σχεδιασμού.
> Ενημερώνεται συνεχώς — χρησιμεύει ως μόνιμη αναφορά για implementation.
> Τελευταία ενημέρωση: 2026-06-16

---

## 1. Gamification Metrics Redesign

### 1A. Τα 4 νέα metrics (αντικαθιστούν τα υπάρχοντα badges)

| Metric | Ορισμός |
|--------|---------|
| **Motivation** | % των τελευταίων 10 εβδομάδων όπου ο χρήστης έκανε ≥ `weekly_workout_target` workouts |
| **Consistency** | Consecutive training days streak. Off-days (max 3/εβδομάδα, user-configurable) δεν σπάνε το streak |
| **Perseverance** | Για τις τελευταίες 7 training days (εξαιρώντας off-days): μέσος όρος `(1 - deviation_ratio)` per exercise, βασισμένο σε modification tracking |
| **Advancement** | Πλήθος Hall of Fame PR improvement events (νέα εγγραφή + κάθε φορά που score ξεπερνά το προηγούμενο) |

### 1B. Perseverance deviation rules (verbatim απόφαση)

- **Skipped exercise:** deviation = `sets × prescribed_reps` (total reps)
- **Skipped set:** deviation = `sum of reps of all exercises in that set`
- **Time field:** `|prescribed_mins - actual_mins| / prescribed_mins`
- **Other numeric field:** `|prescribed - actual| / prescribed`
- **No modification logged:** deviation = 0

### 1C. Advancement — σχέση με PR system (verbatim)

> "Γ — Advancement μετράει αποκλειστικά Hall of Fame PRs (user-defined PRs). Τα auto-execution PRs εξακολουθούν να υπάρχουν για badges (total_prs) αλλά δεν επηρεάζουν το advancement metric."

- PR badge στο hero αφαιρείται εντελώς
- Auto-execution PR achievements (`pr_event:*`) παραμένουν για milestone badges

### 1D. Hero section αλλαγές (verbatim)

> "have no badges in hero and remove at all PR badge. leave the ones below hero as is now (apart from removing PR badge). also in hero a welcoming message to user, personalized, must be on top"

- **Hero:** Personalized welcome message πρώτο (π.χ. `"Good morning, {nickname}!"` + dynamic line βάσει δεδομένων: streak, τελευταίο workout κτλ.)
- Quote block παραμένει κάτω από το welcome
- Zero badges/chips στο hero
- Stats strip: **4 cards** αντί για 3 (Motivation / Consistency / Perseverance / Advancement). Αφαιρούνται: Total workouts, Total PRs

### 1E. Off-Days Setting — Full Hexagonal Stack (verbatim)

> "i didn't see you take provision to create the surface where user sets his/hers days-off. this must be implemented across all layers of hexagonal architecture"
> "now the surface for setting days-off must be in a special section in profile and if it is not set manually, a warning must be in landing page (with insightful, intuitive, detailed explanation and setup instructions)"

**Schema:** Νέο `user_gamification_preferences` table:
```
id: uuid
user_id: uuid (unique FK)
off_days: {:array, :integer}  # [0..6], max 3, 0=Sun…6=Sat
inserted_at / updated_at
```

**Port:** `GamificationStore` + 2 callbacks:
- `get_user_preferences(user_id)`
- `upsert_user_preferences(user_id, params)`

**Application:** `GetGamificationPreferences` query + `UpdateGamificationPreferences` command

**Domain:** Calculators (`DayStreakCalculator`, `PerseveranceCalculator`, `MotivationCalculator`) δέχονται `off_days: [integer]` ως explicit parameter — zero DB coupling

**API:**
```
GET  /api/gamification/preferences
PUT  /api/gamification/preferences  → {off_days: [1, 6]}
```

**Frontend — Profile page surface:**
Νέο section στο `/profile` με τίτλο "Training Schedule". Checkboxes για 7 ημέρες (Δευ–Κυρ), max 3 επιλέξιμες. Save button. Εξήγηση: *"Selected days are excluded from your streak and perseverance calculations — so a rest day won't break your progress."*

**Frontend — Landing page warning (αν δεν έχει ρυθμιστεί):**
Prominent info banner πάνω από το stats strip, μόνο αν `preferences === null`:
> ⚠️ **Set your rest days for accurate metrics**
> Your Consistency, Perseverance and Motivation scores exclude your scheduled rest days — but we don't know which days those are yet.
> Without this, your streak may break on days you never planned to train.
> → [Set your rest days in Profile]

Εξαφανίζεται μόλις αποθηκευτούν preferences (ακόμα και empty array = "I train every day" είναι valid).

### 1F. Schema additions στο `user_stats`

```elixir
field :motivation_score,    :float,   default: 0.0
field :perseverance_score,  :float,   default: 0.0
field :advancement_count,   :integer, default: 0
# current_streak / longest_streak: αλλάζουν σημασία σε DAYS (migration μηδενίζει)
```

---

## 2. Pantheon (Hall of Fame PR System)

### 2A. Naming (verbatim)

> "pantheon is great"

Επίσημο όνομα: **Pantheon**. Παντού — routes, UI labels, API paths, module names.

### 2B. Placement (verbatim)

> "B+A — Section στο landing page + dedicated page"

- Landing page: block section (κάτω από workout history) με summary + link
- Full page: `/my-workouts/pantheon`

### 2C. Features (verbatim από αρχικό αίτημα + διευκρινίσεις)

- Χρήστες προσθέτουν PR ως free text (όνομα)
- Separate field για score (αριθμός)
- Unit: `min+secs | reps | sets | kcals | m | kg` — field κατά την προσθήκη, εμφανίζεται **inline** με το score (π.χ. "142.5 kg"), **όχι** ξεχωριστή στήλη
- `higher_is_better: boolean` — **πολύ subtle**, tiny `↑`/`↓` icon στο top-right corner του score, muted color (`var(--dim)`). Hover tooltip: "Higher score is better" / "Lower score is better". Κανένα label δίπλα.
- `beaten_on: date` (default: today)
- **Ιστορικό:** Όλες οι τιμές αποθηκεύονται. "History ▾" button → expands inline στο card
- **CRUD:** add / edit (creates history entry) / delete (removes entirely)
- **Search:** Fuzzy, Meilisearch-based, user-scoped. Search bar πάνω από τα cards.
- **Share:** Button στο card → `POST /api/prs/:id/share` → pre-filled DM message
- **Full page:** Scrollable, **χωρίς pagination**. Νέα PR στην κορυφή.

### 2D. Card design (verbatim)

> "i prefer the style of this hall of fame to not resemble an accountant's or excel's table. it must be something to celebrate PRs and show-off. so maybe a board with PRs in every line where each PR is a special card, rather than a thin row in a table is better"

```
┌─────────────────────────────────────────────┐
│  BACK SQUAT                        Jun 15   │
│                                             │
│       142.5 kg                        ↑     │
│                                             │
│  [History ▾]         [Share →]  [Edit] [✕] │
└─────────────────────────────────────────────┘
```

- Score: **μεγάλο, prominent**, unit inline
- `↑`/`↓`: tiny, top-right corner, `var(--dim)` color
- Highlight/accent color ανά card (βάσει unit ή palette variety)

### 2E. Schema

```
user_pr_records
  id: uuid
  user_id: uuid (FK)
  name: string (free text, PR title)
  current_score: float
  unit: enum (mins_secs | reps | sets | kcals | m | kg)
  higher_is_better: boolean
  beaten_on: date
  inserted_at / updated_at

user_pr_history
  id: uuid
  pr_record_id: uuid (FK → user_pr_records)
  score: float
  beaten_on: date
  inserted_at
```

### 2F. API endpoints

```
GET    /api/prs               → list (+ search?q=)
POST   /api/prs               → create
PATCH  /api/prs/:id           → update (auto-logs history)
DELETE /api/prs/:id           → delete
GET    /api/prs/:id/history   → full history
POST   /api/prs/:id/share     → returns formatted DM message
```

---

## 3. Workout Modification Tracking

### 3A. During execution (verbatim)

> "in every exercise (more accurately, WOD execution step) there will be one button that when clicked, brings up a small window with the selected step's data as separate fields that can be edited. if user clicks save modifications, this window closes, and the edited fields are logged as modification."

- Κάθε execution step έχει "Modify" button
- Modal με editable fields (prescribed values pre-filled)
- Save → logs structured modification

### 3B. Finish wizard (verbatim)

> "this modification survey also comes up at the finish of the workout... maybe make it a 3-step wizard when finishing a workout: 1 step see and approve or edit scores, 2nd step apply any modifications -if any- to any field of the workout, any step, any parameter, and 3rd step leave a review. all these steps are optional, so they can be skipped"

**3-step wizard στο workout completion:**
1. **Scores** — review/edit section scores
2. **Modifications** — pre-populated από in-workout modifications, μπορούν να προστεθούν νέες, οποιοδήποτε step/parameter
3. **Review** — optional review submission

Όλα τα steps είναι skippable.

### 3C. Coach/Admin modifications (verbatim)

> "we must make it possible for admins/coaches to add modifications to users' workouts as well"

- Admins/coaches μπορούν να προσθέτουν modifications σε athletes' executions (νέο endpoint)
- Αυτές συμπεριλαμβάνονται στον perseverance υπολογισμό

### 3D. Schema addition στο `workout_executions` (verbatim — approved)

```elixir
field :exercise_modifications, {:array, :map}, default: []
# Κάθε entry:
# {
#   exercise_id: string,
#   step_label: string,       # human-readable label
#   field: string,            # "reps" | "sets" | "kg" | "kcal" | "time_mins" | "distance_m"
#   prescribed_value: float,
#   actual_value: float | nil,
#   skipped: boolean,
#   logged_at: datetime
# }
```

### 3E. During Execution UI (approved)

- Κάθε active step: **"Modify this step"** button (subtle, secondary style)
- Click → small modal με pre-filled prescribed values, editable fields, "Skipped entirely" checkbox
- Save → appends to `exercise_modifications`, subtle "modified" dot/indicator στο step
- Optimistic update + debounced sync

### 3F. 3-Step Finish Wizard (approved)

- **Step 1 — Scores:** Review/edit section scores (existing, minimal changes). Skippable.
- **Step 2 — Modifications:** Pre-populated από in-workout mods. "Add another" button. Edit/delete existing. Skippable.
- **Step 3 — Review:** Optional review. Skip/Finish.

### 3G. Coach/Admin modifications (approved)

- Admin drill-down: νέο "Modifications" tab για athlete execution
- Coach μπορεί να προσθέσει/επεξεργαστεί modifications (ίδιο format)
- Endpoint: `POST /api/executions/:id/modifications`
- Συμπεριλαμβάνονται στον perseverance υπολογισμό

---

## 4. Workout Creation Hotkeys + Notes

### 4A. Notes (verbatim)

> "there must be the choice to add notes after a section or next to an exercise (these notes must be shown also in preview and in final workout)"

> "since these are created at workout creation time and only admins/coaches can create workouts, A is the only logical option" (coaching cues, readonly για athletes)

- `section_note: string` field σε workout sections
- `exercise_note: string` field σε workout exercises
- Εμφανίζονται σε `WorkoutPreviewDetail` (readonly)
- Εμφανίζονται κατά την εκτέλεση (readonly)

### 4B. Hotkeys — Final Key Bindings (approved)

> "using plain letters is dangerous. we should use a combination of special keys + the letters you proposed"
> Solution: `Alt+letter` prefix + `document.activeElement` guard (suppress when input/textarea focused)

| Hotkey | Action |
|--------|--------|
| `Alt+E` | Add exercise στην active section |
| `Alt+S` | Add new section |
| `Alt+V` | Add variations στο selected exercise |
| `Alt+A` | Open advanced settings |
| `Alt+P` | Set progressive load |
| `Alt+N` | Add/focus note |
| `Alt+K` | Duplicate selected section (Alt+D avoided — browser conflict) |
| `Alt+/` | Toggle shortcuts modal |
| `Escape` | Close open panels/modals |
| `Tab` / `Shift+Tab` | Navigate exercises (guard: canvas focus only) |
| `Backspace` | Delete selected exercise (guard: not in input) |

**Implementation:** `useEffect` keydown listener στο `WorkoutCreationCanvas` level. Guard: `if (document.activeElement instanceof HTMLInputElement || document.activeElement instanceof HTMLTextAreaElement) return;`

### 4C. Hotkeys display (approved)

- **A:** Tooltip hints on hover: `"Add Exercise (Alt+E)"`
- **B:** Subtle `?` button στο `CanvasHeader` top-right → modal με shortcuts σε 3 στήλες (Section / Exercise / Navigation)

---

## 5. SlotPopup — Member View Redesign

### 5A. Αποφάσεις (verbatim)

> "the confirmation mode should not be shown (but if it is set to by confirmed by coach and he hasn't confirmed yet, a message must communicate that 'booking must be approved by class's coach. He is notified. Wait a while...'). the class capacity should also not be shown in side panel (only class's card in calendar)."

> "make the members' workout side panel look like athletes' workout side panel, meaning that: scale chips are outside workout's section, on the top, below workout title and are color-coded. side panel follows accordion pattern where there are two sections (one the message conversation and the other section everything else, workout-related), they are collapsible and only one can be expanded each time. there is a section for conversation chat thread just like in athletes (this is private thread for members as well - between member and class creator i.e. admin)"

### 5B. Structural changes to SlotPopup (non-admin view)

**Sticky header (unchanged structure):**
- Training type label (color per workout type)
- Workout title
- `+ Add to Calendar` button
- **NEW: Scale chips row** — directly below title, outside any accordion. Color-coded per scale level (distinct color per slug, from a fixed palette, not `var(--primary)` for all). Chip για "Base" + one per scale level. Active chip = filled, inactive = outlined.

**Αφαιρούνται από non-admin view:**
- "Capacity" info box (`approved_booking_count/capacity`)
- "Participation approval" info box ("Auto-confirmed" / "By coach")
- "Deadline to book" info box (remains only for admin)

**Προστίθεται (pending state):** Αν `!slot.auto_approve && slot.current_user_booking?.status === "pending"`:
> Banner: *"Booking must be approved by the class's coach. He is notified. Wait a while…"*
> Styled: subtle info banner, `var(--warning)` border/color, non-alarming.

### 5C. Accordion pattern (matches AssignedWorkoutPanel)

Δύο sections, collapsible, μόνο ένα expanded ταυτόχρονα:

**Section A — "Workout Details"** (default expanded):
- Workout preview (`WorkoutPreviewDetail`) με `activeScaleOverride`
- Admin/coach note (αν υπάρχει)
- Booking status + Cancel booking button
- Reschedule option (αν επιτρέπεται)

**Section B — "Conversation"** (collapsed by default):
- `ChatSection` με `contextType="class_booking"`, `contextId={slot.current_user_booking.id}`
- Private thread μεταξύ member και class creator (admin)
- Εμφανίζεται μόνο αν υπάρχει `current_user_booking` (δεν μπορείς να κάνεις chat πριν κάνεις booking)

### 5D. Scale chip color palette

Κάθε scale level slug παίρνει χρώμα από fixed palette (index-based):
```
index 0 (RX/Base): var(--primary)
index 1:           var(--warning)
index 2:           var(--success)
index 3:           #a78bfa  (violet)
index 4+:          var(--dim)
```
Consistent με οποιαδήποτε ονομασία scale level — χρώμα βάσει sort_order.

---

## 6. Workout History — View Toggle + Filters

### 6A. Αποφάσεις (verbatim)

> "there should be two chips to toggle view between grid view or list view and also, there must be a button to filter results by date or by workout type or if they have modifications or the status (completed/in progress)"

- **Toggle chips:** Grid view / List view (default: grid, υπάρχον layout)
- **Filter button** → dropdown/panel με:
  - Date range picker
  - Workout type (multi-select)
  - Has modifications (boolean chip)
  - Status: completed / in progress

---

## Status

| Section | Status |
|---------|--------|
| 1. Gamification Metrics | ✅ Πλήρως αποφασισμένο |
| 1E. Off-Days setting (full stack) | ✅ Πλήρως αποφασισμένο |
| 2. Pantheon (Hall of Fame) | ✅ Πλήρως αποφασισμένο |
| 3. Modification Tracking | ✅ Πλήρως αποφασισμένο |
| 4. Hotkeys + Notes | ✅ Πλήρως αποφασισμένο |
| 5. SlotPopup member redesign | ✅ Πλήρως αποφασισμένο |
| 6. History Toggle + Filters | ✅ Πλήρως αποφασισμένο |
