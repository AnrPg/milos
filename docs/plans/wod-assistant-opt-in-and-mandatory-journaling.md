# Plan: Per-gym opt-in WOD assistant, timers-only WODs and mandatory WOD journaling

**Status:** Proposed — research done, nothing implemented.
**Audience:** the agent that will implement it. Read `AGENTS.md` first (TDD, hexagonal rules, ADR-first, i18n, "LIVE TEST").
**Scope:** API (`apps/api/`) and web (`apps/web/`). New migrations are additive only.
**Suggested ADRs:** ADR-137 is already reserved by `docs/plans/free-text-wod-editor-declutter-and-inline-suggestions.md`, so this plan uses **ADR-138** (per-gym assistant + encrypted key), **ADR-139** (sectioned manual WODs + timers-only execution) and **ADR-140** (mandatory WOD reporting with snooze). Deferred items start at **TD-104** in `docs/technical_debt.md`.
**Related:** ADR-050 (modification patches), ADR-109 (structured-first workouts), ADR-118 (training log), `docs/superpowers/specs/2026-07-19-journal-first-app-redesign.md` (Journal thesis: "planned and actual are distinct").

---

## 0. What the owner asked for (summary)

1. **Assistant is optional per gym.** It runs only if the gym enabled it **and** gave an API key, loaded dynamically (per request). The current env key (`GEMINI_API_KEY`) stays as fallback and for dev experiments.
2. **Per-WOD opt-out.** In a gym with the assistant enabled, a WOD author can still choose not to use it for a given WOD. Such a WOD has **no automatic step-by-step execution**: the coach must set up **one timer per section/subsection**, and the athlete manually marks section *x* complete and starts timer *y*.
3. **Authoring without the assistant is per section.** The coach clicks **"Add new section"**, writes free text for that section and attaches (sets up) the section's timer. "Add new section" has a **hotkey**, with a default that each user can change in **account settings**.
4. **Warning before execution**, only in gyms that enabled the assistant (there users sometimes get guided execution and sometimes not): "The coach hasn't enabled automatic step-by-step execution for this WOD; you can use only the timer(s)." Gyms without the assistant never see it (their users only ever know the timers-only UX).
5. **Post-WOD reporting differs by WOD kind.**
   - **Structured/canonical WOD:** progress is logged automatically, and **variations override the prescribed defaults** — variations made during the WOD *or* after it.
   - **Non-structured WOD (only this case):** the user types records: an exercise field (fuzzy-matching dropdown over the canonical exercise list **and** the alias table, plus **chip suggestions** below it for exercises matched from the WOD text), a **value** field, a **unit** field and an optional **details** field (reps/kg/observations).
6. **Reporting is mandatory.** The user can only **snooze** it; it keeps coming back as a notification. After **three snoozes** it stops and the WOD is stored as **"not in journal"** with a clear indicator. WOD journaling is the bare minimum the app requires; users can still journal more.

---

## 1. Context (what exists today)

### 1.1 The assistant and its key

| Piece | Where | Notes |
|---|---|---|
| Port | `apps/api/lib/palee/workouts/ports/workout_text_analyzer.ex` | `outline/2`, `parse/2`, `proofread/2`, each `(text, options)`. Errors: `:analyzer_not_configured \| :analyzer_unavailable \| :analyzer_invalid_response`. |
| Adapter | `apps/api/lib/palee/infrastructure/workouts/gemini_workout_text_analyzer.ex` | `run/4` reads `Application.get_env(:palee, :gemini)`; blank `api_key` → `{:error, :analyzer_not_configured}`; key sent as `x-goog-api-key`. The whole config keyword list flows through `loop/6`, so overriding `api_key` there is the only adapter change needed. |
| Env config | `apps/api/config/runtime.exs:11-18` | `api_key: GEMINI_API_KEY`, `model`, `thinking_level`, `parser_thinking_level`, `icon_model`. **This is the "hardcoded" key** — one key for the whole instance. |
| Query | `apps/api/lib/palee/workouts/queries/analyze_free_text.ex` | Runs proofread (async), outline, parse + ≤2 repairs. `options` (a plain map) reaches every adapter call → per-gym credentials can ride along. Adapter resolved via `config :palee, :workout_text_analyzer` (`config.exs:131`; `FakeWorkoutTextAnalyzer` in test). |
| Use case | `apps/api/lib/palee/application/analyze_free_text_workout.ex:10` | Receives `tenant_context` but **ignores it**. |
| Controller | `PaleeWeb.AdminWorkoutFreeTextController.analyze/2` (`…/admin_workout_free_text_controller.ex:144`), route `router.ex:524` | `:analyzer_not_configured` → 503 `analyzer_not_configured`; other errors → 502. |
| Icon suggester | `Palee.Infrastructure.Ai.GeminiWorkoutIconSuggester` (ADR-136), called by `Application.SuggestWorkoutIcon` from an Oban job whose args already carry `organization_id` | Uses the **same** env key. Must follow the same per-gym resolution. |
| Web | `apps/web/src/components/workouts/creation/FreeTextWorkoutEditor.tsx` (`analyze()` :228, `publish()` :320, `buildPayload` ~:880), `FreeTextAnalysisPanel.tsx` (button :67, `errors.notConfigured` :502) | **No capability flag.** The web learns that the assistant is missing only from the 503. |

### 1.2 Gym settings and secrets

- `organization_settings` (`Organizations.OrganizationSetting`): typed columns (timezone, locale, branding…) + a free-form `settings :map` (holds `"onboarding"`, join link). Tenant-side write: `EctoOrganizationStore.put_organization_settings_entry/3` (:681). Vendor write: `update_organization_settings/4` (:711).
- Admin settings UI: `apps/web/src/app/admin/settings/page.tsx` → `components/admin-settings.tsx` (Appearance, Branding, Gamification, Levels, Finance, Scheduling, Notifications). API: `AdminSettingsController` (GET/PATCH `/admin/settings`) → `Application.GetAdminSettings` / `UpdateAdminSettings`.
- **No encryption at rest exists** (no Cloak, no vault). The only stored secret is the VAPID private key, plaintext, global, **write-only over the API** (responses expose only `vapid_private_key_configured`). `Notifications.PushConfig.config/0` already implements **"DB value, else env fallback"** — the pattern to copy.

### 1.3 Authoring and the "structured vs not" signal

- `MasterWorkout.authoring_mode ∈ structured | quick_text | free_text` (`master_workout.ex:126`), plus `free_text_body`, `free_text_document`, `has_many :sections`.
- A `free_text` WOD publishes with **no sections** if the assistant did not run (`EctoWorkoutStore.validate_publish_body/1` :1376).
- The free-text WOD has **one** whole-workout timer preset in `workout_metadata["free_text_timer"]` (`web/src/lib/free-text-timer.ts:26`, server mirror `execution/domain/timer_presets.ex`).
- Structured sections already own one timer each: `workout_sections.timer_config` (`workouts/domain/timer_config.ex`), formats in `workout_dsl/vocabulary.ex:154`, plus `rest_before_next_section_seconds`, `transition_seconds`.
- The legacy structured canvas (`WorkoutCreationCanvas.tsx`, hidden behind `SHOW_AUTHORING_MODE_SWITCHER = false`) already has `Alt+N` = add section and `Alt+E` = add exercise, hard-coded (`:315-330`, listed in `ShortcutsModal.tsx`).
- **"Is this WOD runnable step-by-step?"** is decided only on the web: `usesManualTimer()` (`web/src/lib/workout-execution-mode.ts:26`) = free_text AND (no real exercises OR `timer_inference === "incomplete"`). The execute page (`app/workouts/[id]/execute/page.tsx` ~:51) uses a *different* rule (`authoring_mode === "free_text"` only) → the two can disagree today.

### 1.4 Execution, variations, completion

- Guided execution: `TimerSequenceBuilder.build/1` (server) → `GET /api/workouts/:id/timer-sequence` → `ExecutionMode.tsx` + `useExecutionStore` + `useWorkoutTimer`. Segments auto-advance on expiry; for_time/untimed are manual check-off (design doc §7).
- Unstructured execution: `FreeTextExecutionMode.tsx` with local `FreeTextRun` state (localStorage), one preset → segments with `section_id: "free-text"`; on completion it just `router.push("/")`.
- Variations: `exercise_variations` (per exercise × scale level) are materialized by `WorkoutMaterializer` **before** the sequence is built. Changes made during/after execution are ADR-050 patches (`{canonical_value, actual_value}`) on `workout_executions.exercise_modifications`, via `Application.AddExecutionModifications` (works **after completion** too; no status check). Patches made mid-workout in `ModificationModal` are **kept in React state only** and posted at finish (`ExecutionMode.tsx:202/341`) → lost on reload/crash.
- Finish: `FinishWizard.tsx` (score → modifications → confirm), **every step has Skip** (:142, :458, :660). `CompleteWorkout` → `CompleteExecution` → `ProcessWorkoutCompletionJob` (gamification) → PubSub `workout:completed`.
- Today nothing turns prescription + patches into "what I actually did" rows; patches are read for display/export only.

### 1.5 Journal, catalog, units, notifications

- Journal page `app/journal/page.tsx` → `JournalWorkouts.tsx` lists **executions** (`useWorkoutVault`), detail in `ExecutionPerformanceModal`. Training log (`training_log_entries`, ADR-118) is a separate standalone-entry table (`performed_exercises` = name/ref/sets/reps/load/load_unit/distance/… — no generic value+unit), UI only on the landing page (`TrainingLogSection.tsx`).
- **Exercise catalog lives in code**, not a table: `WorkoutDsl.ExerciseCatalog` (~115 `{slug, label, category, aliases}`), `resolve/1` (exact normalized label/alias). Fuzzy: `WorkoutAssistant.Tools.lookup/1` (Jaro ≥ 0.82, top 3). Served only via the **admin-scoped** `GET …/admin/workouts/dsl/manual` → members cannot fetch it. **No alias table.** Web fuzzy scorer: `fuzzyResultFor/fuzzyScore` in `web/src/lib/workout-dsl-suggestions.ts:193-240`. Generic `Combobox` exists only under `components/admin/finance/shared/`.
- **No unit module**: unit lists are scattered (TrainingLogPolicy kg/lb + m/km/mi; authoring metadata kg/lb/bodyweight/pct_1rm; PRs `mins_secs reps sets kcals m kg`; analysis `reps secs kcal meters`). Conversion exists only privately inside `Tools.convert/3`.
- Notifications: `notifications` table (type is an `Ecto.Enum` **and** a DB check constraint replaced by each new-type migration — latest `20261015104000_add_access_ended_notification_type.exs`), `NotificationEventJob`, `PushDispatchJob`, `PushMessageBuilder` (no action buttons). **No snooze/remind-later anywhere**; reminders are cron-only; no job uses `schedule_in`/`scheduled_at` yet.
- Account preferences: `users` has `preferred_locale`, `completed_tours` — **no preferences map**, no shortcut storage.

---

## 2. Research summary (what best practice says)

_Links were not re-fetched while writing this plan; the implementer should skim them before Phase 0._

**Bring-your-own-key (BYOK) for LLM features.** Multi-tenant SaaS products that let a tenant supply an LLM key treat it as a write-only secret: encrypt at rest with an app-held key (envelope/AEAD), never return it, show only "configured · …last4" and a **Test** action, rotate by overwrite, and resolve per request so a change applies immediately ([OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html), [OWASP Cryptographic Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html)). AES-256-GCM via Erlang `:crypto.crypto_one_time_aead/6` is in OTP, so **no new dependency** (AGENTS.md requires human approval for new deps such as Cloak). Store a key id/version next to the ciphertext so the master key can be rotated. Never log the key; scrub it from `Req` error logs.

**Feature gating and capability discovery.** The client should learn availability from a capability flag, not from a failing call (avoids a dead "Check with assistant" button and enables the pre-execution warning). Fail closed: a gym that enabled the assistant but whose key is invalid sees an explicit "key rejected" state, not a silent fall-through to the platform key (which would spend the platform's quota without consent).

**Consistency/transparency when automation is sometimes present.** When the same surface sometimes offers automation and sometimes not, tell the user up front what mode they are in and why ([NN/g — Visibility of system status](https://www.nngroup.com/articles/visibility-system-status/), [Google PAIR — Mental models & expectations](https://pair.withgoogle.com/chapter/mental-models/)). Users who never see automation don't need the message (owner's point 4).

**Manual multi-timer flows.** Common interval-timer apps that chain several timers expose an explicit "Done → Next" control between blocks and never auto-start the next block unless configured; the next block's name and duration is previewed before start. Large targets, one primary action per screen state.

**Mandatory but humane prompts.** Forcing functions work when the required task is small, the deferral has a bounded number of uses, and the end state is visible ([NN/g — Push notifications](https://www.nngroup.com/articles/push-notification/)). Escalating intervals beat fixed repetition; avoid nagging at night (respect local quiet hours). Web Push `actions` buttons are supported in Chromium-based browsers but **not** in Safari/iOS ([MDN — `showNotification` actions](https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerRegistration/showNotification#actions)) → "Snooze" must also work in-app.

**Typed manual logging.** Autocomplete over a canonical vocabulary with aliases reduces duplicates; offer suggestions derived from context (here: the WOD text) as tappable chips; keep value and unit as separate fields so values stay numeric and comparable; allow free text only in an optional details field ([WAI-ARIA APG — Combobox](https://www.w3.org/WAI/ARIA/apg/patterns/combobox/)). The Journal spec (§4.3) already says "typed nullable metrics", which this matches.

**Rebindable hotkeys.** Store bindings by **physical key code** (`KeyboardEvent.code`, e.g. `KeyN`), not `key`, otherwise `Alt+N` breaks on macOS (Option+N is a dead key) and on non-Latin layouts (12 locales incl. `el`, `ru`, `ar`, `he`); refuse browser-reserved combos (Ctrl/Cmd+N/T/W, Ctrl+Tab) and detect conflicts with other app shortcuts ([MDN — KeyboardEvent.code](https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/code), [WCAG 2.1.4 Character Key Shortcuts](https://www.w3.org/WAI/WCAG22/Understanding/character-key-shortcuts.html)).

---

## 3. Goals / non-goals

**Goals**
1. Assistant availability is a per-gym, per-request decision, with the gym's own encrypted key; env key is a controlled fallback.
2. One explicit, server-derived **execution kind** per published WOD: `guided` or `timers_only`.
3. A per-section manual authoring mode (free text + mandatory timer per section) with a rebindable "Add new section" hotkey.
4. A timers-only execution UI with explicit "Mark section complete" → "Start next timer", and the transparency warning in assistant-enabled gyms.
5. Guided WODs auto-log effective performance = prescription (materialized for the scale) **overridden by** variations made during or after the WOD.
6. Timers-only WODs get a typed record form (exercise combobox + chips, value, unit, details).
7. Reporting is mandatory with ≤ 3 snoozes, then "not in journal" with a visible badge.

**Non-goals**
- No change to the assistant's data contract (`FreeTextWorkoutAnalysis`), prompts or the inline-suggestions editor plan (ADR-137).
- No per-gym model selection or billing/usage metering (record as TD).
- No multi-provider support (Gemini only; the port stays provider-neutral).
- Class-timer (`class_timers`, coach-driven big screen) behaviour is unchanged; it already reads per-section timers.
- Standalone training-log entries (ADR-118) are not made mandatory.
- No change to gamification credit rules (see §6 open question).

---

## 4. Target design

### 4.1 Per-gym assistant settings + dynamic key (ADR-138)

**Data (Organizations context, new table, additive migration):**

```
organization_assistant_settings
  organization_id   uuid PK/FK  (RLS forced, like other tenant tables)
  enabled           boolean  default false
  provider          text     default 'gemini'   -- check constraint
  api_key_ciphertext bytea   null
  api_key_iv        bytea    null
  api_key_tag       bytea    null
  api_key_key_id    text     null               -- which master key encrypted it
  api_key_last4     text     null
  key_status        text     default 'unknown'  -- unknown | valid | rejected
  key_checked_at_utc timestamptz null
  updated_by_id     uuid, timestamps, lock_version
```

A dedicated table (not a key inside `organization_settings.settings`) keeps the secret out of every settings read and lets RLS/permissions differ.

**Encryption:** `Infrastructure.Secrets.AeadVault` (AES-256-GCM via `:crypto`), master key(s) from env `ASSISTANT_KEY_ENCRYPTION_KEYS` (`id:base64,…`, first = current). Port `Organizations.Ports.SecretVault` (`encrypt/1`, `decrypt/1`). Boot fails in `:prod` if the variable is missing **and** any row has a ciphertext; in dev/test a fixed test key is configured.

**Resolution (Application layer):** `Application.ResolveAssistantCredentials.call(organization_id)` →

| Gym `enabled` | Gym key | Result |
|---|---|---|
| false | any | `{:error, :assistant_disabled}` |
| true | present | `{:ok, %{api_key: decrypted, source: :gym}}` |
| true | absent | env fallback **only if** `config :palee, :assistant_env_fallback` allows this org → `{:ok, %{api_key: env, source: :platform}}`; else `{:error, :assistant_key_missing}` |

`assistant_env_fallback` = `:all` in `dev`/`test`, and in `prod` an allowlist from env `ASSISTANT_ENV_FALLBACK_ORG_IDS` (default empty). That keeps the current key for dev experiments and for gyms the platform owner chooses to sponsor, without spending it silently on everyone. **No fallback when a gym key is rejected** (fail closed, show "key rejected").

**Plumbing:** `AnalyzeFreeTextWorkout.call(context, params)` resolves credentials first and passes `options.credentials` to `Workouts.analyze_free_text/2`; extend the port's `options` type with `optional(:credentials) => %{api_key: String.t()}`; the Gemini adapter uses `options.credentials.api_key` when present, else env (keeps tests and scripts working). `SuggestWorkoutIcon.call/2` does the same with the job's `organization_id`. A 401/403 from Gemini maps to a new error `:analyzer_key_rejected` → set `key_status = rejected` (via an Organizations command, through PubSub or the Application service) → HTTP 422 `assistant_key_rejected`.

New controller errors: `assistant_disabled` (403), `assistant_key_missing` (409), `assistant_key_rejected` (422). Keep 503 for the env-only legacy path.

**Capability flag:** add `assistant: %{enabled: bool, available: bool}` to the tenant bootstrap payload the web already loads for branding/role (find the org-context endpoint used by the org layout) and to `GET /admin/settings`. `available` = resolution would succeed and `key_status != rejected`. Never include the key.

**Admin UI:** new section **"Workout assistant"** in `components/admin-settings.tsx` (owner/admin only): toggle; write-only API key input (`type=password`, placeholder "Configured · ••••1a2b"); **Test key** (calls a cheap `models.get`/1-token request through a new `POST /admin/settings/assistant/test`); **Remove key**; status chip (valid / rejected / not checked); short note on data sent to Google. Turning the toggle on without a key and without fallback shows an inline error and saves `enabled=true` only together with a key (or when fallback applies).

### 4.2 Per-WOD choice and the sectioned manual editor (ADR-139)

**New authoring mode `sectioned_text`** (add to the `authoring_mode` inclusion list; additive). A `sectioned_text` WOD is a list of `workout_sections` rows, each with:
- `title` (optional, e.g. "A. Strength"), `free_text_body` + `free_text_document` (**new nullable columns on `workout_sections`**, TipTap JSON as on master workouts), `timer_config` (existing), `rest_before_next_section_seconds`/`transition_seconds` (existing), `parent_section_id`/order (existing hierarchy → subsections).
- **No exercises.** Publish validation (`validate_publish_body/1`): ≥ 1 section, every section has non-blank text **and** a timer whose format is not `untimed` (for_time count-up is allowed — it is "a timer"). Error keys per section so the editor can point at the offending one.

**Where the coach picks it:**
- Gym assistant **disabled** → the "New workout" page opens the sectioned editor directly; the free-text + assistant editor is never shown.
- Gym assistant **enabled** → the new-workout page shows a two-option segmented control at the top: **"Write with assistant (guided execution)"** (current free-text editor) / **"Write by sections (timers only)"**. Default = assistant. Switching keeps text: assistant→sections puts the whole body into section 1; sections→assistant concatenates sections with their titles as headings (confirm dialog because per-section timers are dropped).
- A free-text WOD whose analysis never ran or failed can also be published as `free_text` without structure (today's behaviour). Keep it, but its execution kind is `timers_only` with its single preset (see §4.3), and in assistant-enabled gyms the editor shows "Publishing without the assistant → athletes get timers only" before Publish.

**Sectioned editor UI** (`components/workouts/creation/SectionedWorkoutEditor.tsx` + `SectionCard.tsx`): title/type header as in the declutter plan; a vertical list of section cards, each with a compact TipTap editor (reuse `FreeTextEditingAssist`/toolbar from the declutter plan), a **Timer** button opening a popover with `FreeTextTimerFields`-style fields bound to that section's `timer_config` (reuse `PreviewSectionTimer` for the preview), "Add subsection", reorder (drag + keyboard Alt+↑/↓), delete. A big **"+ Add new section"** button at the end shows its hotkey hint (e.g. `Alt N`). A missing timer shows a red "Timer required" chip on the card; Publish lists missing timers.

**Hotkey preference:**
- `users.preferences jsonb not null default '{}'` (Identity, additive). Shape: `{"shortcuts": {"workout.add_section": {"code": "KeyN", "alt": true, "ctrl": false, "shift": false, "meta": false}}}`. Domain `Identity.Domain.ShortcutPreferences` (pure): known action ids + defaults, validation (one non-modifier key, ≥ 1 modifier except F-keys, reserved combos rejected, no duplicates across actions).
- API: `GET/PATCH /api/me/preferences` (OpenAPI first). Web: new **"Keyboard shortcuts"** section in account settings (`app/profile` or the account settings page) with "Press new shortcut…" capture, Reset to default, conflict message.
- Web hook `useShortcut(actionId, handler)` reading prefs (TanStack Query) and matching on `event.code` + modifiers; replace the hard-coded `Alt+N` in `WorkoutCreationCanvas.tsx` and use it in the sectioned editor; `ShortcutsModal` renders the user's bindings (layout-aware label via `navigator.keyboard?.getLayoutMap()` when available). Works inside contentEditable (the handler runs at document level, as today).

### 4.3 Execution kind and timers-only execution (ADR-139)

**Server-derived `execution_kind`** (`Workouts.Domain.ExecutionKind.derive/1`, pure): `guided` iff the workout has runnable structured sections (exercises present, `timer_inference != "incomplete"`), else `timers_only`. Expose it on every workout read DTO and on the timer-sequence response. Replace `usesManualTimer()` and the execute-page check with this field (fixes today's disagreement). Also expose `assistant_gym: bool` (the org's `assistant.enabled`) on the execution start/read payload so the warning decision is server-truth.

**Timer sequence for timers-only:** `TimerSequenceBuilder.build/1` learns `sectioned_text`: one segment group per section from its `timer_config`, carrying `section_id`, `section_title`, `section_text` (rendered body) and **`advance: :manual_section`**. Rest/transition segments stay automatic. Legacy `free_text` (one preset) maps to one section titled with the workout title, so both legacy and new timers-only WODs run in the same component.

**Timers-only execution UI** (`components/workouts/execution/TimersOnlyExecution.tsx`, replaces `FreeTextExecutionMode` for both cases; uses `useExecutionStore` + `useExecutionSync` so progress is server-synced like guided mode instead of localStorage-only):

```
┌─────────────────────────────────────┐
│ ⚠ Your coach hasn't enabled          │ ← only if assistant_gym; dismiss per WOD, shown again next WOD
│   step-by-step execution for this    │
│   WOD. Use the timers below.         │
├─────────────────────────────────────┤
│ Section 1 of 3 · A. Strength         │
│        AMRAP 12:00  →  08:41         │
│ (section text, read-only)            │
│ [ ✓ Mark section complete ]          │ ← primary
├─────────────────────────────────────┤
│ Next: B. Conditioning · EMOM 10×1:00 │
│ [ ▶ Start timer ]   (after complete) │
└─────────────────────────────────────┘
```

- The warning is a **blocking interstitial on the Ready screen** (must press "Start with timers") and then a slim banner during execution. Shown iff `assistant_gym && execution_kind == timers_only`. Never shown in gyms without the assistant. Copy (en): "Your coach hasn't enabled automatic step-by-step execution for this WOD, so you can use only the timer(s). Mark each section complete when you finish it."
- When a timer expires the section is **not** auto-completed: the timer shows "Time!" and the primary button stays "Mark section complete". The athlete may also complete early (timer stops). After completion the next section is previewed and starts **only** on "Start timer" (no auto-start). Store records `section_elapsed_ms` and completion timestamps per section.
- Pause/resume, wake-lock, cast view, offline caching as in guided mode.

### 4.4 Reporting after the WOD (ADR-140)

#### A) Guided WODs — automatic log with variations

- Persist mid-WOD modifications **immediately** (`POST /executions/:id/modifications` from `ModificationModal`, optimistic, idempotent by `patch_id`) instead of holding them in React state.
- New pure domain function `Execution.Domain.EffectivePerformance.derive(materialized_sections, checked_step_ids, section_scores, patches)` → performed rows per exercise/set (`exercise_ref`, name, sets/reps/load/unit/duration/distance/calories, `source: :prescribed | :patched | :skipped`). Rules: start from the **materialized prescription for the athlete's scale level** (scale variations already applied by `WorkoutMaterializer`), then apply ADR-050 patches in `logged_at` order (last wins per field): `*_changed` overrides the value, `exercise_substituted` swaps the exercise ref/name, `skipped` marks the row skipped; unchecked steps count as not performed only if the execution was finished early.
- On completion the finish screen shows the derived log ("Here is what we logged") with edit affordances that **create patches** (never rewrite the prescription), then "Save to journal". Edits after the WOD go through the same `AddExecutionModifications` from the Journal detail (`ExecutionPerformanceModal` gets an "Edit actuals" mode). Journal and PR detection read effective performance, not raw prescription.
- For guided WODs, confirming this screen **is** the report (one tap if nothing changed), which satisfies §4.5.

#### B) Timers-only WODs — typed records (this case only)

Record row: **Exercise** (combobox) · **Value** (numeric; time entered as `mm:ss`) · **Unit** (select) · **Details** (optional text ≤ 500: "reps/kg/observations"). "+ Add record"; at least one record or an explicit "I did it but have nothing to record" (counts as reported, e.g. mobility).

- **Exercise combobox** (`components/journal/ExerciseCombobox.tsx`, WAI-ARIA combobox): options from the canonical catalog (labels) **and** the alias table; matching an alias shows "Pec deck (alias of *Pec Deck Fly*)" and stores the canonical `exercise_ref`. Ranking reuses `fuzzyScore` from `workout-dsl-suggestions.ts` (extract to `lib/fuzzy-match.ts`). Unknown names allowed ("Use “xyz” as custom") with `exercise_ref = null`.
- **Chips** under the field: exercises matched in the WOD text, tap to fill. Computed server-side by a deterministic, non-LLM `Workouts.Domain.ExerciseMentions.extract(text, catalog)` (normalize, tokenise, longest-match n-grams ≤ 4 against labels + aliases, Jaro ≥ 0.92 only for multi-word candidates) so it works in gyms **without** the assistant. Stored at publish in `workout_metadata["exercise_mentions"]` (list of `exercise_ref`) and recomputed on edit; chips already used in a row are hidden.
- **Alias table:** keep the code catalog canonical; add `exercise_aliases (id, organization_id null = global, alias, normalized_alias, exercise_ref, created_by_id, timestamps; unique (organization_id, normalized_alias))`, seeded from `ExerciseCatalog` aliases by a migration-time data step (or a mix task). `ExerciseCatalog.resolve/1` gains an alias-store lookup through a port so the DSL parser, the assistant's `lookup_exercises` tool and the combobox share one source. Coaches can add gym aliases later (TD).
- **Member-reachable catalog endpoint:** `GET /api/org/:slug/exercise-catalog` → `{exercises: [{ref, label, category}], aliases: [{alias, ref}]}` with ETag + long cache (today's catalog is only on the admin DSL manual route).
- **Units:** new pure `Workouts.Domain.Units` (single list + labels + dimension + conversion, absorbing `Tools.convert/3`): `reps, rounds, kg, lb, m, km, mi, cal, sec, min, mm:ss (time), % `. The unit select defaults from the chosen exercise's category capabilities (strength → kg, cardio → cal/m, bodyweight → reps).
- **Storage:** new `workout_executions.performed_records jsonb default '[]'` (`{id, exercise_ref, name, value, unit, details}`), validated by `Execution.Domain.PerformedRecordPolicy` (max 50, value ≥ 0, unit ∈ Units). Written via `Application.ReportWorkoutResults` (`PUT /api/executions/:id/report`). Executions stay the Journal source (spec §3.3: the Journal renders the execution, no duplicate journal workout).

### 4.5 Mandatory reporting with snooze (ADR-140)

**State on `workout_executions`** (additive columns):

```
report_status        text   default 'not_required'  -- not_required | pending | reported | not_journaled
report_snooze_count  int    default 0               -- 0..3
report_next_reminder_at_utc timestamptz null
reported_at_utc      timestamptz null
```

Existing rows stay `not_required` (no backfill nagging). On completion: `report_status = pending`.

**Pure policy** `Execution.Domain.ReportPolicy`:
- `report(state, now)` → `reported` (allowed from `pending` **and** from `not_journaled` = late report, flagged `late: true`).
- `snooze(state, now, tz)` → if `snooze_count < 2`: count+1, `next_reminder_at = now + interval(count)` (defaults **1st → +2 h, 2nd → +6 h**), shifted out of quiet hours 22:00–08:00 local to 08:00; if this is the **3rd** snooze: count = 3, `status = not_journaled`, no more reminders. ("After three snoozes it stops.")
- `reminder_ignored(state, now)` → an unanswered reminder (no report, no snooze within 12 h of delivery) counts as a snooze, so a WOD can never stay pending forever.

**Flow:**
1. Finish screen → report step (guided: confirm derived log; timers-only: record form). **No Skip.** The only secondary action is **"Snooze (n of 3 left)"**; the 3rd press warns: "This WOD will be stored as not in your journal."
2. Closing the app on the report step = pending; on next app open a **non-dismissable sheet** "You have 1 WOD to report" appears (Report / Snooze), driven by `GET /api/me/pending-reports`.
3. `WorkoutReportReminderJob` (Oban, queue `:notifications`, `scheduled_at: next_reminder_at`, `unique: [keys: [:execution_id, :snooze_count]]`): if still `pending`, create notification type **`workout_report_due`** (new enum value + check-constraint migration; visible in inbox) and push with deep link `/journal/report/:execution_id`. Push payload includes `actions: [{action: "report"}, {action: "snooze"}]`; the service worker handles `snooze` by calling `POST /api/executions/:id/report/snooze` (Chromium); Safari/iOS opens the page with both buttons. Reporting/snoozing cancels pending jobs (`Oban.cancel_all_jobs` by args).
4. `not_journaled` WODs show in Journal (`JournalWorkouts`, `ExecutionPerformanceModal`, landing history) with a clear badge **"Not in journal"** (warning colour + icon + text, not colour alone) and a "Report now" action (late report).

**Ownership:** state and commands in **Execution** (`Commands.ReportExecution`, `SnoozeExecutionReport`, `MarkExecutionNotJournaled`); notification side effects via PubSub `execution:report_due` → Notifications; Application services `ReportWorkoutResults`, `SnoozeWorkoutReport`, `ListPendingReports`. No controller touches Repo.

---

## 5. Implementation plan (phases — each independently shippable, TDD)

Commit order inside each phase follows AGENTS.md (migration → schema → domain → commands → queries → context API → application service → OpenAPI → controller/router → generated client → frontend). Run `mix palee.architecture` and `mix precommit` (API) and `npm run lint`, `npm run test`, `npm run i18n:check` (web) before every push.

**Phase 0 — ADRs and safety net.** Write ADR-138/139/140 (decisions in §4, open questions in §6) and update `docs/adr/README.md`. Add Playwright safety tests: (a) free-text publish with stubbed analysis, (b) guided execution start→finish, (c) free-text execution start→finish. These stay green throughout.

**Phase 1 — Per-gym assistant (ADR-138).**
1. Migration `organization_assistant_settings` (+ RLS policy like other tenant tables).
2. `Infrastructure.Secrets.AeadVault` + port, unit tests (round-trip, tamper → error, unknown key id, rotation).
3. Schema, `Organizations.Domain.AssistantSettingsPolicy` (pure: enable needs key-or-fallback, last4), commands `UpdateAssistantSettings`, `RecordAssistantKeyStatus`; query `GetAssistantSettings`; context API.
4. `Application.ResolveAssistantCredentials` (integration tests for each row of the §4.1 table incl. fallback allowlist).
5. Extend port options with `credentials`; adapter uses it; map 401/403 → `:analyzer_key_rejected`; scrub key from logs. Update `FakeWorkoutTextAnalyzer` to assert credentials are passed.
6. `AnalyzeFreeTextWorkout` + `SuggestWorkoutIcon` resolve credentials (tests: disabled gym → no adapter call).
7. OpenAPI: admin settings `assistant` block (write-only `api_key`, read `configured`, `last4`, `key_status`), `POST /admin/settings/assistant/test`, new error codes, capability flag in tenant bootstrap. Controllers, router, ConnCase tests (owner/admin only; key never in any response — assert on full JSON).
8. `npm run generate:api`; web "Workout assistant" settings section; editor hides/disables "Check with assistant" from the capability flag; i18n (12 locales).
9. Config: `ASSISTANT_KEY_ENCRYPTION_KEYS`, `ASSISTANT_ENV_FALLBACK_ORG_IDS`, `assistant_env_fallback` per env; document in `.env.example`/deploy docs.

**Phase 2 — Sectioned manual authoring + hotkey (ADR-139).**
1. Migration: `workout_sections.free_text_body/free_text_document`, `authoring_mode` gains `sectioned_text`; `users.preferences`.
2. Domain: publish validation for `sectioned_text` (every section text + non-untimed timer), `ShortcutPreferences`; tests.
3. Workouts commands/store accept sectioned payloads; draft autosave as today (`draft_data`).
4. OpenAPI + controllers: workout create/update with sections+text; `GET/PATCH /api/me/preferences`.
5. Web: `SectionedWorkoutEditor`, `SectionCard`, section timer popover (reuse `FreeTextTimerFields` bound to `timer_config`), mode chooser on the new-workout page (only when assistant enabled), `useShortcut`, account "Keyboard shortcuts" section, `ShortcutsModal` from prefs, migrate `WorkoutCreationCanvas` to `useShortcut`. Unit tests for key matching (`event.code`, macOS Option, Greek/Russian layouts), conflict validation.

**Phase 3 — Execution kind + timers-only execution (ADR-139).**
1. `ExecutionKind.derive/1` + tests (structured, free_text analysed, free_text unanalysed, `timer_inference: incomplete`, sectioned_text); expose on workout DTOs and timer sequence; `assistant_gym` on execution payloads.
2. `TimerSequenceBuilder` support for `sectioned_text` and legacy single-preset free_text with `advance: :manual_section`; tests.
3. Web: replace `usesManualTimer()` and the execute-page check with `execution_kind`; `TimersOnlyExecution.tsx` on `useExecutionStore` (manual complete → preview → start next; no auto-start), warning interstitial + banner; delete `FreeTextExecutionMode` after parity (keep `storeFreeTextRun` reader for in-flight runs one release).
4. Playwright: assistant-enabled gym shows warning; assistant-disabled gym does not; two-timer WOD requires complete-then-start.

**Phase 4 — Guided auto-log with variations (ADR-140 part A).**
1. Persist `ModificationModal` patches immediately (optimistic + retry); tests for reload during WOD.
2. `EffectivePerformance.derive/4` pure + exhaustive unit tests (scale variation, each patch type, substitution, last-wins, skipped, finished early).
3. Query/Application service exposing effective performance on execution reads; finish screen "What we logged" + edit-as-patch; Journal "Edit actuals".

**Phase 5 — Typed records for timers-only WODs (ADR-140 part B).**
1. `Workouts.Domain.Units` (+ move `Tools.convert/3` onto it); tests.
2. Migration `exercise_aliases` + seed from `ExerciseCatalog`; alias store port; `ExerciseCatalog.resolve/1` + `Tools.lookup/1` read through it; tests that DSL parsing is unchanged.
3. `ExerciseMentions.extract/2` + tests (aliases, plurals, multi-word, punctuation, Greek text, no false positives on "for", "rest"); store mentions at publish.
4. `GET /api/org/:slug/exercise-catalog` (member scope, ETag).
5. `workout_executions.performed_records`, `PerformedRecordPolicy`, `ReportWorkoutResults`; OpenAPI; controller.
6. Web: `ExerciseCombobox` (APG combobox, keyboard, RTL), chips, value/unit/details row, unit default by category.

**Phase 6 — Mandatory reporting + snooze (ADR-140 part C).**
1. Migration: report columns on `workout_executions`; notification type `workout_report_due` (replace the check constraint as in `20261015104000_…`).
2. `ReportPolicy` pure + tests (3 snoozes → not_journaled, late report, quiet hours across DST, ignored reminder).
3. Commands, `WorkoutReportReminderJob` (scheduled), cancellation, PubSub → Notifications, push payload with actions; tests with `Oban.Testing`.
4. `GET /api/me/pending-reports`, `POST …/report/snooze`, report endpoint sets `reported`.
5. Web: finish flow without Skip, snooze button with remaining count, app-open pending sheet, service-worker `notificationclick` action handling, "Not in journal" badge + "Report now" in Journal/landing history.

**Phase 7 — Docs and polish.** Fill ADR Implementation Notes, add TDs (below), update user guides under `docs/guides/` if they describe execution or the editor, LIVE TEST every flow in §Acceptance with two gyms (assistant on with own key; assistant off).

**Technical-debt candidates:** TD-104 per-gym model choice/usage metering; TD-105 coach-managed gym aliases UI; TD-106 analytics on snooze/not-journaled rates per gym; TD-107 bringing manual records into PR detection (`self_reported` provenance per Journal spec §11); TD-108 class-timer participants' reporting (members who ran the WOD only on the big screen).

### Acceptance criteria
1. A gym with the assistant **disabled** never calls Gemini (verified by the fake adapter), never shows assistant UI, and opens the sectioned editor directly.
2. A gym with the assistant **enabled + own key** uses that key on the next request after saving it (no restart); the key is never returned by any endpoint or written to logs; a rejected key shows "key rejected" and does **not** fall back to the env key.
3. Env key works for every gym in dev/test and only for allowlisted gyms in prod.
4. A `sectioned_text` WOD cannot be published while any section lacks text or a (non-untimed) timer; "Add new section" works with the default hotkey and with a user-rebound one, including on macOS and Greek/Russian layouts.
5. `execution_kind` is the only source for guided vs timers-only on the web; in assistant-enabled gyms a timers-only WOD shows the warning before start; in assistant-disabled gyms it never does.
6. In timers-only execution, section *y*'s timer never starts until section *x* is marked complete and the athlete presses Start.
7. A guided WOD with a scale variation and two mid-WOD patches (one before reload, one after) logs effective values with both patches applied; an after-WOD edit changes the journal values without changing the prescription.
8. A timers-only WOD's report accepts canonical, alias and custom exercise names; chips list exercises named in the WOD text; values are numeric with a unit from `Units`.
9. Finishing any WOD leaves it `pending` until reported; Skip is gone; the 3rd snooze stores it as `not_journaled`, no more reminders fire, and the Journal shows the "Not in journal" badge; reporting later turns it into a late `reported` entry.
10. All new copy in 12 locales; `npm run i18n:check`, `mix precommit`, `mix palee.architecture`, Playwright and axe pass.

### Project rules the implementer must follow
- Hexagonal + bounded contexts: credentials resolution is an **Application** service; Workouts never reads Organizations tables; Notifications reacts to Execution events via PubSub.
- OpenAPI first; never hand-edit `apps/web/src/api/generated/`.
- **No new dependency** without human approval (use OTP `:crypto`, not Cloak).
- Migrations additive only (new columns/tables/enum values); notification type change = replace the check constraint as previous migrations do.
- i18n for all 12 locales; logical CSS properties for RTL; TDD; LIVE TEST.

---

## 6. Risks and open questions (defaults given; the owner can override)

1. **Env fallback in production** — default: only allowlisted gyms (`ASSISTANT_ENV_FALLBACK_ORG_IDS`). Alternative: fallback for every enabled gym without a key (simpler, but the platform pays for all).
2. **Does `for_time` (count-up) satisfy "a timer per section"?** Default: yes; `untimed` does not.
3. **Snooze intervals** — default +2 h then +6 h, quiet hours 22:00–08:00 local; 3rd snooze ends it immediately. Should intervals be gym-configurable? Default: no (TD).
4. **Late reporting after `not_journaled`** — default: allowed, marked "late". Alternative: permanent.
5. **Gamification** — default: unchanged (completion still counts for streaks even if not journaled). Alternative: streak credit only after reporting (stronger forcing, but punishes users with notifications off).
6. **Existing completed executions** — default: `not_required`, no retroactive prompts.
7. **Master-key loss** makes gym keys unreadable → gyms must re-enter keys; document backup of `ASSISTANT_KEY_ENCRYPTION_KEYS` with the DB backups.
8. **Web Push actions** don't work on iOS/Safari → snooze there needs opening the app (acceptable; in-app sheet is the primary surface).
9. **Hotkey default `Alt+N`** conflicts with some Linux window managers and screen readers' quick-nav keys; the rebind setting is the mitigation, and the shortcut is ignored while a screen-reader browse mode has focus outside the editor.

## 7. Sources
- [OWASP — Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [OWASP — Cryptographic Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html)
- [Erlang/OTP — `crypto:crypto_one_time_aead/6`](https://www.erlang.org/doc/apps/crypto/crypto.html#crypto_one_time_aead/6)
- [NN/g — Visibility of system status](https://www.nngroup.com/articles/visibility-system-status/)
- [Google PAIR — Mental models](https://pair.withgoogle.com/chapter/mental-models/)
- [NN/g — Push notifications](https://www.nngroup.com/articles/push-notification/)
- [MDN — `ServiceWorkerRegistration.showNotification()` actions](https://developer.mozilla.org/en-US/docs/Web/API/ServiceWorkerRegistration/showNotification#actions)
- [WAI-ARIA APG — Combobox pattern](https://www.w3.org/WAI/ARIA/apg/patterns/combobox/)
- [MDN — `KeyboardEvent.code`](https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent/code) · [WCAG 2.2 — 2.1.4 Character Key Shortcuts](https://www.w3.org/WAI/WCAG22/Understanding/character-key-shortcuts.html)
- Internal: `docs/superpowers/specs/2026-07-19-journal-first-app-redesign.md` (§3.3, §4.3, §11), `docs/superpowers/specs/2026-06-05-gym-app-design.md` (§7 Execution Mode), ADR-050, ADR-109, ADR-118, ADR-136.
