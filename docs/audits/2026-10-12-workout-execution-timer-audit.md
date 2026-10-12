# Workout Execution & Timer — Business + UX/UI Audit

**Date:** 2026-10-12
**Scope:** Structured-workout execution (`/workouts/[id]/execute`), free-text execution
(`/workouts/free-text/execute`), the timer engine (backend `TimerSequenceBuilder` + frontend
`useWorkoutTimer`), and the timer *authoring* fields that feed it.
**Method:** Static code reading of the full execution path, a cross-check of what authoring
can produce against what execution consumes, and a review against published UX/UI guidance and
shipping competitor timers. Findings marked **[Bug]** come from reading the code and naming
the exact lines. None were reproduced in a running app; §8 lists how to confirm each one.

---

## Implementation status

**P0 shipped (2026-10-12)**: T1, T3, T4, U1, U2/U9, V1, V6, V7, as listed in the §8 roadmap.

- **T1** turned out wider than §3 describes. With the editor's defaults, **7 of 19** formats were
  rejected: HRR, Death By, Cluster, both ladders and Pyramid (a default `time_cap_seconds: 0`
  fails the `> 0` check), plus Complex EMOM whenever per-minute intervals were set. The editor now
  builds `timer_config` from `apps/web/src/types/timer-config-contract.json`, and
  `timer_config_contract_test.exs` keeps that file identical to the backend vocabulary. All 19
  default payloads now normalize.
- **Known limitation**: Complex EMOM per-minute interval lengths (`interval_seconds_N`) have no
  backend field. They are no longer sent, so the section saves with its base interval.
- **Finish path**: opening the review now persists a pause first. A persisted pause already
  includes the current segment's elapsed time in the stored totals, so completion no longer adds
  it a second time. This also fixes the score-on-the-last-segment path, which used to count that
  segment twice.

---

## 0. Executive summary

The execution experience has a solid technical foundation: a versioned, server-backed progress
model, offline check-off queueing, multi-tab sync, and a pure, testable timer-sequence builder.
The problems sit at the edges where real workouts meet that engine. They fall into four groups:

1. **The timer can't express many of the workouts coaches actually write.** "5 rounds for time",
   "Death by burpees (EMOM)", rest between sets, rest between sections, and transition time can
   all be authored, but the timer engine silently ignores them. Execution then shows something
   different from what the coach programmed.
2. **Some formats can't be saved at all from the visual editor.** The authoring form for
   *HRR*, *Death By* and *Cluster* sends fields the backend rejects, or leaves out fields the
   backend requires. This is the root of "the timer is hard to set".
3. **The timer isn't reliable in a real gym.** The screen is allowed to sleep, there is no
   sound or vibration, the clock stops advancing when the phone locks or the tab goes to the
   background, and each segment boundary loses time to a network round-trip. Scoreable interval
   workouts (Tabata/EMOM) interrupt the athlete with a score dialog **every interval**.
4. **The UI is built for reading, not for training.** It shows one exercise at a time behind a
   "tap anywhere" card. There is no round counter, no "up next", no undo for a mistaken tap,
   and *Finish* is a one-tap trap with no way back. The main button text fails WCAG contrast.

**Business impact:** execution is the moment of truth for both revenue streams. In-person class
members and remote athletes judge the product, and the coach, by whether the timer "just works"
mid-WOD. Every forced manual workaround (a phone stopwatch next to the app, or a whiteboard for
rounds) erodes trust in the programming and lowers the share of sessions that get logged with a
score. Those logged scores feed streaks, PRs, the leaderboard, and coach analytics. Fixing the
P0 items below is a prerequisite for the gamification and coaching features to have good data.

---

## 1. Business perspective

### 1.1 Who executes, and what they need

| Persona | Context | Must-haves from execution |
|---|---|---|
| **Gym member in class** | Phone on the floor 1–3 m away, sweaty hands, loud music, coach running a wall clock | Glanceable clock, audible cues, near-zero interaction, quick score entry at the end |
| **Remote athlete** | Alone, often in a commercial gym, follows the coach's program | The app *is* the coach: the timer must run the session exactly as programmed (rests, rounds, transitions) and capture results reliably for coach feedback |
| **Coach / admin** | Writes programming, reviews results | What they author is what the athlete gets; results are complete and comparable (scores, modifications, notes) |

### 1.2 Value levers

- **Retention and adherence:** a session that's frictionless to start and finish gets repeated.
  Streaks, PRs and challenges only work if execution reliably produces a completion with a score.
- **Coach productivity and credibility:** remote programming is a premium, personal service. If
  "rest 90 s between sets" or "5 rounds" don't show up in execution, the athlete sees the
  coach's program as sloppy, even though the authoring was correct.
- **Data quality for analytics:** `section_scores`, `segment_cycle_counts`, elapsed times and
  modifications feed leaderboards and coaching analytics. Today, rounds in AMRAP/for-time depend
  on the athlete tapping every single exercise, so the data is sparse or wrong.
- **Differentiation:** dedicated WOD timers (SmartWOD Timer: 54K ratings at 4.9★) win on
  glanceability, audio, and a tap-anywhere round counter. Milos's advantage is that the timer is
  *already loaded with the coach's workout*. That advantage only counts if the timer itself is
  as good as a dedicated one.

### 1.3 KPIs to instrument (none are measured today)

| KPI | Definition | Why |
|---|---|---|
| Start → finish completion rate | completed / started executions | Main health metric for execution |
| Abandon point | segment index / format at last progress update for non-completed executions | Shows which formats break |
| Score capture rate | completions with a non-auto score on scoreable sections | Data quality for leaderboards and PRs |
| "Next"-tap rate on countdown segments | manual skips / countdown segments | High values mean the timer is being bypassed |
| Pause frequency and duration | per execution | Shows confusion or interruptions |
| Time-to-first-rep | launch tap → first segment start | Setup friction |
| Finish-wizard drop-off | wizard opened → saved | Post-workout friction |

---

## 2. Format coverage matrix (authoring → engine → execution)

Legend: ✅ works as authored · ⚠️ works partially · ❌ broken or ignored

| Format | Authoring UI (visual editor) | Timer engine (`timer_sequence_builder.ex`) | Execution UX | Verdict |
|---|---|---|---|---|
| untimed / straight sets / circuit / stations | ✅ | `no_timer`, **no rest timers** | Shows "—", no stopwatch, no rest between sets | ⚠️ |
| for_time | ⚠️ `rounds` not exposed | `countup` + cap; **`rounds` ignored** | List shown once, auto-advances after one pass | ❌ for "N RFT" |
| train_to_exhaustion | ✅ rest field | `manual`; **`rest_seconds`, `rounds`, `time_cap_seconds` ignored** | "Manual", no clock, no rest | ❌ |
| kcal_target | ✅ | `countup` + cap | No kcal progress input | ⚠️ |
| emom / complex_emom | ⚠️ `scoring_mode` and `max_windows` only via other UI | One countdown per interval ✅. `to_failure` makes **100 segments** | Score modal **every minute** if scoreable; no "I failed" action | ⚠️ |
| even_odd | ⚠️ interval not exposed (fixed 60 s) | ✅ | Same per-interval score popup | ⚠️ |
| billat / tabata / custom_hiit | ✅ | Work/rest pairs ✅. **Trailing rest after the final round** | Score popup after **every work and rest** segment if scoreable | ⚠️ |
| amrap | ✅ | `countdown` ✅. `target_rounds` ignored | **No visible round counter**; must tap each exercise each round | ⚠️ |
| edt | ✅ | `countdown` ✅ | Same as AMRAP | ⚠️ |
| death_by | ❌ sends `max_rounds` (unknown field → **save rejected**) | `manual`; **`interval_seconds` ignored**. Death By is an EMOM by definition | No clock at all | ❌ |
| cluster | ❌ `sets` (required) missing → **save rejected** | Set/intra-rest segments ✅. `rest_seconds` between clusters ignored | Sets are "Manual" (no clock) | ❌ |
| hrr | ❌ sends `hr_ceiling_bpm`, `hr_floor_bpm`, `effort_cap_seconds`, `cycles` (all unknown) and omits required `effort_seconds` → **save rejected** | Effort countdown + manual "Recover to HR" | If saved via DSL without effort, a 0 s countdown expires instantly | ❌ |
| ladder_asc / ladder_desc / pyramid | ⚠️ `start/step` derived from first exercise only; `time_cap_seconds` exposed | `manual`; **`time_cap_seconds` ignored** | No clock even though a cap was set | ❌ |
| rest | ✅ | `countdown` ✅ | "Rest" text only, no "up next" preview | ⚠️ |

Cross-cutting metadata that **can be authored but is never executed**: `rest_before_next_section_seconds`,
`rest_after_seconds`, `transition_seconds` (optional on 9 formats), `auto_advance`, per-exercise
`rest-between-sets` / `rest-between-rounds` / `rest-between-sides`, and section `recovery-condition`.
None of these are read by `TimerSequenceBuilder` (confirmed: no references outside parser,
formatter and storage).

---

## 3. Timer engine findings

### P0 — correctness

**T1. [Bug] Authoring form produces timer configs the backend rejects (HRR, Death By, Cluster).**
`apps/web/src/types/workout.ts:269-290` and `FormatContextualFields.tsx:53-75` define fields
(`max_rounds`, `hr_ceiling_bpm`, `hr_floor_bpm`, `effort_cap_seconds`, `cycles` for HRR) that
are not in `Vocabulary` (`vocabulary.ex:83-117`). `TimerConfig.reject_unknown_fields/2` and
`validate_required_fields/2` then fail the section changeset (`workout_section.ex:80`). Cluster
never sends the required `sets`. `toApiPayload` spreads `formatParams` verbatim
(`stores/workout-creation.ts:722`).
*Fix:* generate the frontend field list from the backend vocabulary (the OpenAPI schema or a
`/vocabulary` endpoint), or at minimum align the keys. Add a contract test that, for each
format, round-trips `makeDefaultFormatParams` → `TimerConfig.normalize`.

**T2. [Bug] Rounds, rests, transitions and caps are dropped by the sequence builder.**
`timer_sequence_builder.ex:66-127` ignores `for_time.rounds`, `train_to_exhaustion.rest_seconds/rounds`,
`death_by.interval_seconds`, ladder/pyramid `time_cap_seconds`, `cluster.rest_seconds`,
`transition_seconds`, and section-level rest-between/before-next. *Fix:* the builder should emit:
- `for_time` with `rounds: N` → one countup segment per round sharing a **section-level cap
  clock**, or a single countup with a round counter (preferred, see U3).
- Death By → EMOM-style countdowns (`interval_seconds`, default 60) with the round's target reps
  (`start + step·(n−1)`) in the label. It ends on a "Failed" action.
- Ladder/pyramid with a cap → `countup` with a cap instead of `manual`.
- Transition and section-level rests → an inserted `countdown` "Transition"/"Rest" segment
  (kind `rest`), with an "up next" payload.
- Straight-sets rest (exercise `rest_between_sets`) → a rest countdown after each set check-off
  (client-side, so it doesn't explode the segment count).

**T3. [Bug] Score dialog fires on every interval of a scoreable multi-segment section.**
`ExecutionMode.tsx:311-319` opens `ScoreModal` when *any* segment of a scoreable section
expires or the athlete taps Next. Tabata, EMOM, Billat and Cluster sections are split into many
segments, and each carries `scoreable: true`. The athlete gets a modal every 20 s / every
minute, and the timer is paused while it's open. *Fix:* only prompt on the **last segment of the
section** (`segments[i+1]?.section_id !== segment.section_id`). Accumulate per-interval results
silently; better still, move all score entry to the end (see U8).

**T4. [Bug, race] Stale `elapsed` after a segment change can auto-skip the next segment.**
`useWorkoutTimer.ts:23` keeps `elapsed` in state and only resets it on the next
`requestAnimationFrame`. After `advanceSegment`/`jumpToSegment`, the first render computes
`remaining` from the *previous* segment's elapsed. Example: tap *Next* at 0:25 of an EMOM minute
when the next segment is a 10 s rest. `isExpired` flips to `true`, and `ExecutionMode`'s
`setTimeout(…, 0)` (≈4 ms) usually fires before the next animation frame (≈16 ms) clears it.
The rest segment is skipped. *Fix:* derive elapsed from `segmentStartedAt`/`pausedElapsed`
synchronously during render (`Date.now() - segmentStartedAt + pausedElapsed`), or key the hook
state by `segment_key` and reset it on change. Add a unit test for "advance from long to short
segment".

**T5. Wall-clock drift at every boundary.** Each new segment starts at `Date.now()` *after* a
server round-trip (`movePastCurrentSegment` → `persistProposedMutation`). On a 20-minute EMOM
with a 300 ms RTT, that adds about 6 s of drift, and a coach's wall clock and the app disagree.
*Fix:* the next segment's `startedAt` is `previous.startedAt + previous.duration` (scheduled
time), not "when the server answered". Advance optimistically and persist afterwards. The ADR's
"commit after acknowledgement" rule should exempt timer-driven auto-advance, which is
deterministic, while keeping it for user navigation.

**T6. The clock stops when the phone locks or the tab is backgrounded.** `requestAnimationFrame`
is not called for hidden pages (Chrome docs). Expiry detection, and therefore auto-advance,
stops; when the user comes back, only **one** segment advances. *Fix:* compute the current
position from an absolute schedule: `workoutStart` plus cumulative durations, minus pauses. On
`visibilitychange`, fast-forward through every expired segment in one step. Use
`setInterval(250)` for logic and rAF only for painting.

**T7. Countdown segments of 0 s and trailing rests.** HRR with no `effort_seconds` (possible via
DSL), or Tabata's final "Rest 8/8", produce segments that either expire instantly or waste
time. *Fix:* drop the final rest of an interval block, and skip or validate segments with
`duration <= 0`.

**T8. EMOM `to_failure` generates 100 one-minute segments** (`max_windows || 100`). The header
reads "1 / 112", and the athlete must hit *Finish* to stop. *Fix:* represent it as an open-ended
repeating interval with an explicit "Failed / Stop" action and a score of windows completed.

**T9. Elapsed-time precision.** `commitSegmentElapsed(elapsed * 1000)` uses floored whole
seconds, which loses up to 1 s per segment (about 8 s over a Tabata). For-time scores derive
from this. *Fix:* commit milliseconds from the timestamps.

### P1 — model consistency

- **T10. Two timer implementations.** Free-text execution (`FreeTextExecutionMode.tsx`) has its
  own rAF timer, its own format math and its own labels. It isn't persisted, so a reload loses
  the clock, and it doesn't sync across tabs. Consolidate on one `TimerEngine` (pure TS, fed
  either by server segments or by a quick "timer preset" for free-text).
- **T11. Hard-coded English labels from the backend** (`"Min 1"`, `"Work 1/8"`, `"Intra Rest"`,
  `"Recover to HR"`, `"Odd – Min"`) are shown verbatim in 13 locales. `TimerDisplay.tsx:95` also
  prints the raw enum (`complex_emom`). *Fix:* send structured label data
  (`{kind: "work", round, total}`) and localize on the client.

---

## 4. UX findings (interaction design)

Grounded in: glanceability (the athlete is 1–3 m away and moving), the thumb zone (key actions in
the bottom third), Fitts' law and touch-target guidance (≥ 1 cm / 44 pt / 48 dp), forgiveness
(undo over confirm), and "the screen is secondary": shipping interval timers lead with distinct
audio and haptic cues per phase.

### P0

**U1. No audio, haptics or wake lock.** The codebase has no `AudioContext`, `vibrate`,
`speechSynthesis` or `wakeLock` call. The screen dims and the phone sleeps mid-AMRAP, and the
athlete must watch the screen to know when an interval ends. *Do:*
- Request `navigator.wakeLock.request("screen")` on start and re-acquire on `visibilitychange`
  (the browser releases it when hidden). Release on finish.
- Web Audio beeps: 3-2-1 short beeps before each boundary, a distinct long tone for "work",
  another for "rest", and a fanfare at the end. Optional voice (`speechSynthesis`) for "Rest",
  "Round 3 of 8", "Halfway", "1 minute left".
- `navigator.vibrate` patterns per phase on Android.
- An in-session "sound / voice / vibration" toggle with sound on by default. Audible audio also
  exempts the page from Chrome's background timer throttling.

**U2. Finish is a one-tap trap.** The header *Finish* (`ExecutionMode.tsx:603`) has the same
visual weight as navigation. It opens `FinishWizard`, which has **no way back to the workout**
(the component has no `onCancel` prop), while the timer keeps running underneath. *Do:* move
*End workout* into a pause sheet or behind a long-press. Pause the timer when the wizard opens,
and add "Back to workout".

**U3. No round counter for AMRAP / for-time / EDT / ladders.** `segmentCycleCounts` is tracked
but never shown. To count a round, the athlete must tap through *every exercise* of the round,
one card at a time. In a 12-minute AMRAP with 3 movements over 8 rounds, that's 24 precise taps
on a phone on the floor. *Do:* use a huge "**+1 ROUND**" target (the bottom half of the screen,
SmartWOD-style tap anywhere) with the round count shown next to the clock, plus a small "–1"
undo. Keep per-exercise check-off as an optional "partial reps" entry at the end.

**U4. No undo for check-offs.** Completed steps render as faded, non-interactive rows
(`WorkoutChecklist.tsx:208-235`). A mistaken tap, which is easy because the *whole card* is the
target, can't be reversed without going back a segment, and that resets the segment clock. *Do:*
make done rows tappable to un-check, and show a 5-second "Undo" snackbar after each check-off.

**U5. Pre-start has no "get ready" countdown.** The execution is `active` from the moment the
API creates it (`initExecution` defaults `status: "active"`). Time spent loading the sequence and
navigating counts, and the first interval starts before the athlete has put the phone down.
*Do:* add a ready screen (workout overview, sound check, "Start" button), then a 10-second
(configurable) 3-2-1 countdown. The same pattern already exists for resume.

**U6. Back navigation destroys time.** `jumpToSegment` resets `pausedElapsed` to 0 and does not
commit the elapsed time of the segment being left. The section's measured score and total time
come out wrong. *Do:* commit elapsed on every navigation, and confirm before going back into a
completed timed segment.

### P1

**U7. Tunnel vision: only the current exercise is visible.** For circuits, AMRAPs and EMOM
minutes with several movements, athletes want to see the **whole round** at a glance. *Do:* show
the full round as a compact list with the current item highlighted, and a "Next: Rest 0:10 →
Min 2: 12 Wall balls" strip above the action bar.

**U8. Score entry is split and repeated.** Score is asked in `ScoreModal` mid-workout, and then
again in step 1 of the 3-step `FinishWizard` (Scores → Modifications → Confirm). *Do:* during
the workout, never interrupt. Ask once at the end with prefilled measured values. Collapse the
wizard to a single review screen with inline-editable scores and a collapsed "Anything changed?"
section.

**U9. Pause is a low-emphasis text link** at the top-left (the hardest thumb zone), and while
paused there is no way to end or adjust. *Do:* use a large pause/play control in the bottom bar
and a pause sheet with Resume, Restart segment, Skip, Adjust timer (+/- 30 s), and End workout.

**U10. "Manual" segments look broken.** Cluster sets, ladders, death-by and HRR recovery show
the word "Manual" where the clock should be (`TimerDisplay.tsx:89`). *Do:* always run a
stopwatch (count up) so the athlete sees their time under effort. For HRR recovery, show
"Recover to < X bpm" with a count-up and a "Recovered" button.

**U11. "Next" means two different things.** On countdown segments it skips the remaining time;
on manual segments it marks the step done. *Do:* label by intent: "Skip rest", "Done – next
set", "Finish round".

**U12. Modifications are lost on reload.** `inExecutionModifications` is component state only.
*Do:* persist with the progress snapshot (or IndexedDB, like the offline queue).

### P2

- **U13. Landscape / cast mode** for gym displays: a giant clock only, with the round in the
  corner. It can also serve the coach's class wall display, building on the PubSub channel that
  already exists.
- **U14. Adjust on the fly:** +/- time and +/- rounds while paused (common when a coach changes
  the plan mid-class).
- **U15. Media Session / lock-screen info** (`navigator.mediaSession` metadata with the current
  phase), so the lock screen shows "Work 3/8 · 0:14".

---

## 5. UI findings (visual design)

| # | Issue | Evidence | Recommendation |
|---|---|---|---|
| V1 | Primary CTA text fails WCAG AA: `--text` (#FBF3EE) on `--primary` (#D9743D) = **2.94:1** (needs 4.5:1 at 16 px bold) | `ExecutionMode.tsx:681,698,560` | Use the existing `--primary-contrast` token (`var(--bg)`): ≈ 7:1 |
| V2 | Clock size is 72 px (`text-7xl`) and fixed. From 2 m away, digits need roughly ≥ 25 % of viewport height | `TimerDisplay.tsx` | `font-size: clamp(5rem, 28vw, 14rem)` with tabular numerals; the clock is the hero element |
| V3 | No phase color system. Work and rest look identical; only "expired" turns red | `TimerDisplay.tsx:39-41` | Full-bleed phase background tint: work = primary, rest = calm/info, get-ready = warning, last 3 s = pulse. Never rely on color alone: add labels and icons |
| V4 | No progress visualization of the current interval | — | Circular or linear progress ring around the clock; segment progress bar in the header (replacing "3 / 112") |
| V5 | Round pips are 6 px dots that wrap badly at 30–100 rounds | `TimerDisplay.tsx:58-73` | Show "Round 3 / 8" text when total > 12; pips only for small counts, ≥ 8 px |
| V6 | `h-screen` (100vh) on mobile hides the bottom action bar behind browser chrome | `ExecutionMode.tsx:586` | `h-dvh` plus `pb-[env(safe-area-inset-bottom)]` |
| V7 | **CSS classes run through i18n.** `TimeInput` gets its className from `i18n("w10RoundedLg…")`, and the Arabic and German files contain *translated* class names (`"w-10 مدور-lg …"`, `"abgerundet-lg …"`), which breaks the inputs in those locales | `TimeInput.tsx:49`, `messages/ar.json:1633`, `messages/de.json:1633` | Hard-code the className; remove the key from all locales |
| V8 | Overlays use `absolute inset-0` inside a container that isn't `relative` | `ExecutionMode.tsx` pause/countdown overlays | Use `fixed inset-0` |
| V9 | Raw enum shown as the format hint (`complex_emom`) | `TimerDisplay.tsx:95` | Localized format name |
| V10 | "Modify" (warning-colored) button sits *inside* the tap-to-complete card. A near miss checks off the exercise | `WorkoutChecklist.tsx:180-196` | Move to an overflow "⋯" outside the primary hit area; make the card's check a distinct ≥ 56 px button |

---

## 6. Timer authoring ("hard to set")

1. **Field mismatch** (T1): three formats can't be saved. This is the main cause.
2. **`TimeInput` clamps seconds at 59.** Typing "90" seconds silently becomes 59. It uses two
   `type="number"` boxes (spinner arrows, no `inputmode`), and 0 displays as empty, which looks
   unset. *Do:* a single duration field that accepts `90`, `1:30`, or `1m30s`, with
   `inputmode="numeric"` and **preset chips** (0:10 · 0:20 · 0:30 · 1:00 · 2:00 · 5:00 · 10:00
   · 20:00).
3. **Required parameters are hidden.** `for_time.rounds`, `even_odd.interval_seconds`,
   `emom.scoring_mode` and `max_windows`, and ladder `start/step/min` (derived silently from the
   first exercise) aren't editable where the format is chosen.
4. **No total-duration feedback.** Show a live summary under the fields: "8 × (0:20 work + 0:10
   rest) = 4:00 · ends with work", and a mini timeline of the generated segments. The
   `TimerSequenceBuilder` can serve a preview endpoint so the coach sees *exactly* what the
   athlete will get.
5. **Presets.** One-tap "Tabata 20/10×8", "EMOM 10", "E2MOM 20", "AMRAP 12", "21-15-9 FT cap
   12", "Death By (EMOM)" templates that fill all fields.
6. **Free-text workouts make the athlete configure the timer** (format, minutes, rounds, work,
   rest, interval) before starting. Offer presets plus "last used", and let the coach attach a
   timer preset when writing a free-text workout.

---

## 7. Proposed target design (structured execution)

```
┌──────────────────────────────────────┐
│ ▮▮▮▮▮▮▯▯▯▯  Section 2 of 3 · AMRAP   │  ← segment progress bar, not "3 / 112"
│                                      │
│              WORK                    │  ← phase label + full-bleed phase tint
│           ╭────────╮                 │
│           │  07:42 │                 │  ← clamp(5rem, 28vw, 14rem), progress ring
│           ╰────────╯                 │
│          ROUND 4  (+ 2 reps)          │  ← always visible for repeatable formats
│                                      │
│  ● 10 Wall balls 9 kg      ← current │
│  ○ 10 Box jumps 60 cm                │  ← whole round visible, tap row to toggle
│  ○ 200 m Row                         │
│                                      │
│  Next ▸ Rest 1:00 → Section 3        │
├──────────────────────────────────────┤
│  [ ⏸ ]   [      + 1  ROUND      ]    │  ← ≥ 56 px, bottom third, high contrast
└──────────────────────────────────────┘
Pause sheet: Resume · Restart segment · Skip · ±30 s · End workout
```

Interval formats (EMOM/Tabata) swap the primary button for "Done ✓" (finished the work early,
show rest) and auto-advance on the clock with 3-2-1 beeps. Manual formats show a stopwatch and
"Done – next set", followed by an automatic rest countdown when rest is prescribed.

### Recommended architecture change

Introduce a **pure client `TimerEngine`** (TypeScript, unit-tested like `progress.ts`):

```
schedule = segments.map(s => ({ ...s, plannedStartOffsetMs }))
position(nowMs, startedAtMs, pauses[]) → { segmentIndex, elapsedMs, remainingMs, phase }
```

- The display and cues read from `position()` on a 250 ms interval plus rAF painting, so
  behavior is identical in the background or after a reload.
- Server persistence becomes *fire-and-forget snapshots* for timer-driven transitions, keeping
  the existing lock-version and idempotency semantics. User actions (pause, finish, score)
  still wait for the server's acknowledgement.
- The same engine powers free-text execution (T10) and a future class wall display (U13).

---

## 8. Prioritized roadmap

| Priority | Item | Refs | Effort |
|---|---|---|---|
| **P0** | Align authoring fields with backend vocabulary + contract test | T1 | S |
| **P0** | Score prompt only at the end of a section / workout | T3, U8 | S |
| **P0** | Synchronous elapsed derivation (fix the auto-skip race) | T4 | S |
| **P0** | Wake lock + audio/haptic cues + sound toggle | U1 | M |
| **P0** | Finish: pause + "Back to workout"; move End into the pause sheet | U2, U9 | S |
| **P0** | CTA contrast, `h-dvh`, translated-className bug | V1, V6, V7 | XS |
| **P1** | Schedule-based `TimerEngine` (no drift, background-safe, catch-up) | T5, T6, T9 | M |
| **P1** | Round counter + "+1 round" primary action + undo | U3, U4 | M |
| **P1** | Builder: rounds, death-by EMOM, caps on ladders, transitions, section rests | T2, T7, T8 | M |
| **P1** | Ready screen + get-ready countdown | U5 | S |
| **P1** | Big clock, phase colors, progress ring, next-up strip, full-round list | V2–V5, U7 | M |
| **P1** | Duration input with presets + live timeline preview in authoring | §6 | M |
| **P2** | Localized structured labels | T11, V9 | S |
| **P2** | Unify free-text timer on the engine; timer presets for free-text | T10, §6.6 | M |
| **P2** | Rest-between-sets auto timer for straight sets | T2 | S |
| **P2** | Landscape/cast mode, Media Session, on-the-fly adjust | U13–U15 | M |
| **P2** | KPI instrumentation | §1.3 | S |

### Verification plan for the P0 bugs

- **T1:** ExUnit — `TimerConfig.normalize(Map.merge(%{type: f}, default_params(f)))` for every
  format, with defaults exported from the frontend as a JSON fixture.
- **T3:** Vitest/RTL — scoreable Tabata with 8 rounds; let segments expire. Expect exactly one
  score prompt.
- **T4:** Vitest with fake timers — advance via Next from 25 s into a 60 s segment, followed by a
  10 s segment. Expect `currentSegmentIndex` to stay on the rest segment.
- **T6:** Playwright — start an EMOM, emulate `document.visibilityState = "hidden"` for 3
  minutes, return, and expect the segment index to have moved +3.

---

## Sources

- Chrome for Developers, *Background tabs in Chrome 57* (rAF not called for background pages;
  timer budgets): https://developer.chrome.com/blog/background_tabs
- Chrome for Developers, *Timer throttling in Chrome 88* (intensive throttling; audible pages are
  exempt): https://developer.chrome.com/blog/timer-throttling-in-chrome-88/
- W3C, *Screen Wake Lock API* (secure context; locks released when the page is hidden):
  https://w3c.github.io/wake-lock/
- Adrian Roselli, *Target Size and 2.5.5* (WCAG target size; NN/g's 1 cm guidance):
  https://adrianroselli.com/2019/06/target-size-and-2-5-5.html
- UXPin, *Responsive design for touch devices* (Apple 44 pt / Google 48 dp targets):
  https://www.uxpin.com/studio/blog/responsive-design-touch-devices-key-considerations/
- Parachute Design, *Thumb zone UX* (primary actions in the bottom third):
  https://parachutedesign.ca/blog/thumb-zone-ux/
- SmartWOD Timer (App Store): AMRAP with integrated round counter, background running, large
  landscape numbers: https://apps.apple.com/us/app/smartwod-timer-wod-clock/id1248966041
- SmartWOD Round Counter (tap-to-count rounds): https://apps.apple.com/us/app/-/id1368790169
- Intervo (distinct per-phase vibration and audio cues; eyes-free design):
  https://apps.apple.com/st/app/intervo/id6775499898
- TimerCue (spoken cues continue while the screen is locked):
  https://apps.apple.com/fj/app/timercue-workout-timer/id6748659859
