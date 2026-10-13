# Plan: Declutter the Free Text WOD editor + inline (in-text) assistant suggestions

**Status:** Proposed — research done, nothing implemented.
**Audience:** the agent that will implement it. Read `AGENTS.md` first (TDD, hexagonal rules, i18n, "LIVE TEST").
**Working directory:** `/home/rodochrousbisbiki/MyApps/milos` · **Frontend only:** `apps/web/` (no API changes).
**Suggested ADR:** `docs/adr/ADR-137-…` (inline assistant suggestions as editor decorations). Record deferred items in `docs/technical_debt.md`.

---

## 1. Context (what exists today)

The workout creation page (`/org/:slug/admin/workouts/new?mode=free-text&draft=<id>`) is the only way to create new workouts (`SHOW_AUTHORING_MODE_SWITCHER = false` in `WorkoutAuthoringModes.tsx`). The coach writes the WOD "like on the whiteboard" in a TipTap editor; an LLM assistant (Gemini, behind the `WorkoutTextAnalyzer` port) turns the text into structured data and proposes corrections.

Files that matter:

| File | Role |
|---|---|
| `apps/web/src/components/workouts/creation/FreeTextWorkoutEditor.tsx` (~1000 lines) | Whole page: 4 `CollapsibleRibbon` sections (overview, details, timer, formatting), TipTap editor, footer publish button, right aside with `assistant` / `preview` tabs, all handlers (`analyze`, `handleAccept`, `handleReject`, `handleUndo`, `publish`), helpers `replaceInEditor`, `buildPayload`. |
| `…/creation/FreeTextAnalysisPanel.tsx` (~560 lines) | The assistant side panel: `IssueCard` per issue (Accept / Reject), `SuggestionCard`, `Summary`, `StructurePreview`, `TipsCard`, resolved list with Undo. |
| `…/creation/FreeTextTimerFields.tsx` | Timer preset fields shown when "Attach a timer" is checked. |
| `apps/web/src/lib/free-text-analysis.ts` | Pure review-state logic: `createReviewState`, `acceptIssue`, `rejectIssue`, `undoIssue`, `openIssues`, `replaceFirst`, `isTextCorrection`, `blockingProblems`, `publishFields`. |
| `apps/web/src/lib/workout-dsl-editor-data.ts` | `FREE_TEXT_EDITOR_CLASS`, `sanitizeWorkoutDslPaste`. |
| `apps/web/src/app/globals.css` (`.free-text-rich-content`) | Editor typography. |
| `apps/web/src/api/generated/schema.ts` | **Generated** (`npm run generate:api`) — never hand-edit. |

### The assistant's data contract (do not change it)

`FreeTextWorkoutAnalysis.issues[]` (see `schema.ts`, `FreeTextWorkoutAnalysis`):

```
id, code, severity: "error"|"warning"|"info", required: boolean,
path: "title" | "type" | "sections.0.exercises.1.name" | … | "text",
kind?: "spelling"|"unit"|"number"|"abbreviation"|"format"|"ambiguity"   // only for text_correction
message?, params, current_value?,
suggestion?: { label?, value?, text_edit?: { find: string, replace: string } }
```

**Critical constraint for inline anchoring:** only `text_correction` issues (`path === "text"`, `isTextCorrection(issue)`) carry `suggestion.text_edit` with a *verbatim* `find` string. The server verifies that evidence is verbatim (`Proofreading.verify`). Everything else (`missing_title`, `missing_type`, `assumption`, `invalid_timer`, `unknown_format`, `too_short`…) is about **structured fields**, not a text range → those cannot be highlighted in the text and stay in a panel/summary (see §4.4).

Today `handleAccept` applies a `text_edit` with `replaceInEditor(editor, find, replace)` (first verbatim occurrence inside one text block, formatting preserved) and then `replaceFirst` on `review.analyzedText`. Reject keeps the coach's text. "Stale" = `review.analyzedText.trim() !== body.trim()`.

### What the screenshot shows (the problems)

1. Four stacked accordion headers (`FREE TEXT WOD`, `WORKOUT DETAILS`, `TIMER`, `FORMATTING`) eat ~300 px of vertical space before the coach can type; two of them (overview, timer) contain almost nothing (a title + sentence, one checkbox).
2. The formatting toolbar is an always-visible 2-row wall of 20+ text buttons ("Align left / Align center / Align right", "Strikethrough", `</>`, `“”`…) — most are rarely needed for a WOD.
3. The assistant's output lives far from the text it talks about (right-hand aside, cards with `<del>find</del> → <ins>replace</ins>`), so the coach has to context-switch and mentally map each card to a phrase.
4. The primary action ("Check and publish") is in a footer at the bottom of a scroll area; the assistant's "Analyze" button is in another panel.

---

## 2. Research summary (what best practice says)

**Progressive disclosure.** Show only the few frequently used controls first; reveal the rest on demand; **two levels is the practical norm**, three or more levels confuse users ([NN/g — Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/)). Make the trigger for advanced options easy to spot and clearly labelled. → Today we use accordions *and* a toolbar *and* an aside = too many levels/paths.

**Rich-text toolbar density.** Group actions by context with separators, put overflow behind a "more" control, and remove options the audience does not need ([Velt — Rich text editor UI design](https://velt.dev/blog/rich-text-editor-ui-design-best-practices), [Genesys Spark — Rich Text Editor](https://spark.genesys.com/latest/components/forms-and-inputs/rich-text-editor/usage-XlHQCpoM)). Component libraries built on TipTap move inline formatting into a **selection bubble menu** and link editing into an on-demand popover ([HeroUI Pro — Rich Text Editor](https://docs.heroui.pro/docs/react/components/rich-text-editor)). Touch targets ≥ 44×44 px; keep focus order logical when menus appear (Velt, above).

**Toolbar accessibility.** `role="toolbar"` + `aria-label`; **one tab stop** with arrow keys moving between controls (roving tabindex); use the role only for groups of ≥ 3 controls ([WAI-ARIA APG — Toolbar](https://www.w3.org/WAI/ARIA/apg/patterns/toolbar/)). Toggle buttons need `aria-pressed`.

**Inline suggestion UX (Grammarly / Word / VS Code pattern).**
- Show original and replacement together; **Accept = primary, Dismiss/Ignore = low emphasis**; Dismiss is one click; a "why?" / "learn more" is one click away; "don't show suggestions like this" is secondary ([Grammarly Support — dismissing suggestions](https://support.grammarly.com/hc/en-us/articles/4412837103117-how-to-deactivate-suggestions-in-grammarly-for-windows-or-grammarly-for-mac), [PhiaUI — LanguageTools inline popover](https://phia-ui.hexdocs.pm/PhiaUi.Components.Editor.LanguageTools.md)).
- **Suggestions must never block typing:** if the user keeps typing, their input overrides the suggestion (Smart Compose principle, [web.dev — AI UX patterns](https://web.dev/learn/ai/ux-patterns)).
- Keep each suggestion small and accept it incrementally, with a one-click/one-key accept, to preserve authorship ([arXiv 2601.10236 — Preserving authorship in AI-assisted writing](https://arxiv.org/pdf/2601.10236)).
- Colour is by *issue type* in Word/ProWritingAid and the palettes are inconsistent across products ([ProWritingAid — underline colours](https://help.prowritingaid.com/article/367-what-does-each-underline-color-mean), [Microsoft — underline colours](https://support.microsoft.com/kb/925597)); don't rely on colour alone → vary **underline style** too.
- Limit overload: group/prioritise, show a count ("3 of 7"), allow next/previous stepping; bulk-accept only for high-confidence items (Grammarly grouped suggestions, [Grammarly blog](https://www.grammarly.com/blog/product/grouped-writing-suggestions/)).

**Implementation pattern in TipTap/ProseMirror.** Suggestions are **decorations, not document content**: they are not editable and not saved; accept/reject must run a real transaction and then the decoration set is remapped/rebuilt ([ProseMirror discuss — suggestions as decorations](https://discuss.prosemirror.net/t/suggestions-as-decorations/9027)). Tiptap's own AI Suggestion docs use exactly this: `Decoration.inline` for the range + `Decoration.widget` as the popover anchor, a `--selected` class for the active suggestion, the popover rendered via a React portal and positioned with **Floating UI** ([Tiptap — Customize how suggestions are displayed](https://tiptap.dev/docs/content-ai/capabilities/suggestion/features/display-suggestions)). Tiptap 3 `BubbleMenu` (`@tiptap/react/menus`) is built on Floating UI, supports `shouldShow`, `pluginKey`, `options.placement/offset/flip/shift` ([Tiptap — Bubble Menu](https://tiptap.dev/docs/editor/extensions/functionality/bubble-menu)). We must **not** use the paid `@tiptap-pro` AI Suggestion extension — we build the equivalent ourselves (it is ~150 lines).

**Accessibility of inline suggestions.** Many inline-suggestion UIs are hover-only and therefore not keyboard accessible ([WProofreader docs](https://docs.wproofreader.com/faq/technical/wproofreader/how-would-keyboard-users-be-able-to-access-the-spell-check-suggestions)); WCAG G194 asks for spell-check help and status messages via live regions ([W3C — G194](https://www.w3.org/WAI/WCAG22/Techniques/general/G194)). Our own synthesis (not a standard): non-modal popover (no focus trap), openable by keyboard, `Escape` closes and returns focus to the flagged word, counts announced through `aria-live`.

---

## 3. Goals / non-goals

**Goals**
1. A clean writing surface: the editor is above the fold on a 768 px-high viewport with title, type and Publish all visible; no accordions.
2. Formatting controls follow progressive disclosure (primary row + bubble menu + overflow).
3. The assistant's **wording corrections appear inline** as underlined phrases; click/tap/keyboard opens a small popover with the change and **Accept / Dismiss** (plus "Why?").
4. Field-level assistant output (title, type, timer, assumptions, blocking problems) stays reviewable but moves out of the way into a compact "Review" surface.
5. Keep every behaviour that exists today (autosave, stale detection, undo of resolved issues, blocking checks before publish, timer preset, RTL/12 locales).

**Non-goals**
- No backend/API/OpenAPI change. No change to `AnalyzeFreeText`, issue ids or review-state shape (`ReviewState` stays persisted in `draft_data.free_text_review`).
- Not fixing the `502` on `POST …/free-text/analyze` (separate investigation: the pipeline is long and synchronous; likely gateway timeout). **But** build the new UI so `analysisStatus` (`idle|loading|ready|error`) can later be driven by an async job without UI changes.
- No collaborative/track-changes mode, no ghost-text autocomplete.

---

## 4. Target design

### 4.1 Page layout (desktop ≥ lg)

```
┌────────────────────────────────────────────────────────────────────────────────┐
│ ← Workouts   [ Untitled workout — click to name        ] [Type ▾]  ● Saved     │  ← slim sticky header
│                                    [⏱ Timer] [✓ Check with assistant] [Publish]│
├────────────────────────────────────────────────────────────────────────────────┤
│  B  I  U │ Paragraph ▾ │ • ≡  1. │ 🔗 │ ⋯ More        ↶ ↷                      │  ← 1-row toolbar
├───────────────────────────────────────────────────────────┬────────────────────┤
│                                                           │ Review      Preview │
│  A.                                                       │ 3 suggestions       │
│  Super set                                                │ ▸ Title, type (2)   │
│  Incline Bench Press ~~~~~~~~ …                           │ ▸ Structure 4×2     │
│            ┌──────────────────────────┐                   │ ▸ Timer             │
│            │ “Peck deck” → “Pec deck” │                   │                     │
│            │ spelling · Why?          │                   │                     │
│            │ [Accept]      [Dismiss]  │                   │                     │
│            └──────────────────────────┘                   │                     │
│  15 Peck deck                                             │                     │
├───────────────────────────────────────────────────────────┴────────────────────┤
│ 412 characters · Text changed since last check — Re-check                      │
└────────────────────────────────────────────────────────────────────────────────┘
```

- **Remove** the `overview` ribbon and its description (the `freeTextDescription` copy moves into the editor placeholder / a `?` help tooltip). Remove all `CollapsibleRibbon` accordions.
- **Header (sticky):** title is a borderless large input that looks like a document title (placeholder "Leave empty to let the assistant propose one" → shorten to a translated, shorter hint); type is a compact select/segmented chip; save status as a quiet text on the right; **Publish moves here** (primary button). Keep the existing label logic (`checkAndPublish` → `quickTextPublish`).
- **Timer** becomes a secondary button "Timer" in the header that opens a **popover** containing the existing `FreeTextTimerFields` (and an "Attach a timer" switch). When a preset is attached the button shows a summary chip (e.g. `For time · 12:00`) with a remove ×. Do not render the checkbox row on the page.
- **Assistant trigger:** one button, "Check with assistant", next to Publish (replaces the panel's big card + button). Disabled when no text; shows spinner + `aria-busy` while loading.
- **Aside (right, `lg:` only):** renamed **Review** and **Preview** tabs (existing). Default **collapsed to a thin rail** until a check has run or the coach opens Preview; on `< lg` it becomes a bottom sheet / separate screen (today it stacks below the editor).
- **Footer:** only the character count and the stale chip ("Text changed since last check · Re-check"); no publish button.

### 4.2 Formatting: two levels only

1. **Always visible (primary row, one line):** Bold, Italic, Underline, Highlight, heading `Paragraph ▾` select, bullet list, ordered list, Link, Undo, Redo.
2. **Selection bubble menu** (TipTap `BubbleMenu`, `@tiptap/react/menus`): appears on text selection with Bold / Italic / Underline / Highlight / Link / text colour. Hide while a suggestion popover is open (use `shouldShow` + separate `pluginKey`s).
3. **`⋯ More` overflow popover:** Strikethrough, quote, code block, align left/centre/right, text colour + clear colour, hard break help. This removes ~12 buttons from the main row.
4. Use `role="toolbar"`, `aria-label`, **roving tabindex** (one tab stop; Left/Right arrows; Home/End), `aria-pressed` on toggles, min 44×44 px hit area on touch (`pointer: coarse`). Group with separators. Replace text-glyph buttons (`•`, `1.`, `“”`, `</>`) by real icons **with accessible names** (keep `aria-label`/`title` from the existing `editor*` i18n keys). Replace `window.prompt` for links with an inline link popover (small input, Apply/Remove) — `window.prompt` is a poor, non-themable, non-RTL-friendly pattern.
5. Keep the existing keyboard shortcuts (StarterKit Mod-B/I/U, `Shift-Enter` hard break, Ctrl/Cmd-click quick highlight in `FreeTextEditingAssist`) and document them in a "Keyboard shortcuts" item inside `More`.

### 4.3 Inline suggestions (core feature)

**Scope:** every open issue where `isTextCorrection(issue) && issue.suggestion?.text_edit` (i.e. `openIssues(review)` filtered). Everything else → §4.4.

**Mechanism — a ProseMirror plugin, decorations only (never marks):**

New file `apps/web/src/components/workouts/creation/assistant-suggestions-extension.ts` exporting a TipTap `Extension` (`AssistantSuggestions`) configured with:
- `getSuggestions(): InlineSuggestion[]` (read through a ref, so the extension is created once) where `InlineSuggestion = { issueId, find, replace, kind, severity }`;
- `selectedIssueId` + `onSelect(issueId | null, anchorEl)` callbacks.

Plugin behaviour:
1. On every transaction (`state.apply`): if `docChanged` or the suggestion list changed → **recompute** ranges by locating each `find` in the document (reuse the text-block scanning logic of `replaceInEditor`, extracted into a pure, exported, unit-tested `locateText(doc, find): {from,to} | null`). If `find` is no longer present verbatim, the suggestion **silently disappears** (the user already changed that text — Smart-Compose rule: typing overrides suggestions). Do not map-and-keep stale ranges.
2. Build `DecorationSet` of `Decoration.inline(from, to, { class: "assistant-suggestion assistant-suggestion--<kind-group>", "data-issue-id": id, "aria-describedby": … })`, and add `assistant-suggestion--selected` for the selected one.
3. `handleClick` / `handleDOMEvents.click`: if the target is inside `.assistant-suggestion` → `onSelect(id, element)`. Also open on **keyboard**: command `Mod-.` (VS Code "Quick fix" muscle memory) opens the suggestion at/after the caret; `Alt-ArrowDown` / `Alt-ArrowUp` (or `F8` / `Shift-F8`, implementer to pick and document) step to next/previous in document order and scroll it into view. `Escape` closes the popover and returns focus to the editor with the caret at the flagged word.
4. Decorations are not part of `editor.getJSON()/getHTML()`: nothing is saved into `free_text_document`, `free_text_body` or shown to athletes. Verify with a test.
5. Only the **first** verbatim occurrence of each `find` is decorated (matches `replaceFirst` / accept semantics today). Multiple identical occurrences: out of scope v1 (note in tech debt).
6. IME safety: skip recompute while `view.composing`.

**Popover component** `AssistantSuggestionPopover.tsx` (React, rendered with a portal into `document.body` or the editor's parent; positioned with **Floating UI** — `@floating-ui/react` or `@floating-ui/dom`; `@floating-ui/dom` is already a transitive dependency of TipTap — add it as an explicit dependency; middleware `offset(8)`, `flip()`, `shift({padding: 8})`, `placement: "bottom-start"` — logical placement keeps RTL (ar/he locales exist) correct):
- Content: small label with the kind (`spelling`, `unit`, … via existing `WorkoutAssistant` i18n), the change rendered as `<del>old</del> → <ins>new</ins>` (reuse the markup from `IssueCard`), optional one-line reason (`issueMessage`) behind a **"Why?"** disclosure, and **[Accept] (primary) [Dismiss] (ghost)**. Accept label = `suggestion.label || t("accept")`.
- `role="dialog"`, `aria-modal="false"`, `aria-labelledby`, **no focus trap**; Accept is focused on open **only when opened from the keyboard**; mouse/touch open does not steal editor focus until a button is pressed. `Escape` closes; click outside closes; closes automatically when its suggestion vanishes (text edited).
- Accept → existing `handleAccept(issue)` **but applying the edit at the decoration's exact range** (new `replaceRange(editor, range, replace)`; keep `replaceInEditor` for the panel/fallback path). Dismiss → existing `handleReject(issue)` (keeps coach text; already resolved-list + Undo in the panel). After accept/dismiss, move the caret after the replaced text and, if more suggestions remain, **keep the popover closed** (don't chain-pop).
- Small screens (`max-width: 640px` / `pointer: coarse`): render as a **bottom sheet** with ≥ 44 px buttons instead of a floating bubble (avoids the keyboard covering it).
- Announce: a visually hidden `aria-live="polite"` region says "N suggestions in the text" after a check and "Suggestion applied / dismissed" after actions (WCAG G194 / 4.1.3).

**Visual design of the highlight** (CSS in `globals.css` next to `.free-text-rich-content`; tokens only, no hard-coded colours — use `var(--warning)`, `var(--primary)`, etc., dark-theme aware):
- Don't rely on colour alone: `kind` groups → underline *style*:
  `spelling`, `abbreviation` → wavy underline; `unit`, `number`, `format` → solid thin underline + faint background; `ambiguity` → dotted underline. Severity `error` → thicker underline; `info` → lighter. Max 2 hues.
- `text-decoration-skip-ink: none; text-underline-offset: 3px`; `:hover` and `--selected` add a subtle background (`color-mix(in srgb, var(--warning) 18%, transparent)`).
- `cursor: pointer`; honour `prefers-reduced-motion` (no animations anyway).
- Respect high-contrast / forced-colors (`@media (forced-colors: active)` use `Highlight`/`LinkText` system colours).

**Interaction with the existing review state** (single source of truth stays `ReviewState`):
- `review.analysis.issues` → `inlineSuggestions` via a small pure selector in `free-text-analysis.ts` (`inlineSuggestionsOf(review)`), unit-tested.
- After the coach edits the text, the decoration of an affected suggestion disappears; the issue itself stays "open" in state and the existing **stale** logic is untouched. The panel still lists it (as today) until the next check — but mark it "text changed" so it isn't confusing (optional polish).
- Accept/Dismiss from the popover and from the panel must be equivalent and idempotent (same handlers).

### 4.4 Field-level assistant output (not inline)

Keep, but compact, in the **Review** tab: counts header ("3 suggestions · 2 to review"), then collapsible groups: *Title & type* (missing/assumed → one-click Keep/Reject exactly as `IssueCard` today), *Structure* (existing `StructurePreview`), *Timer* issues, *Resolved (n)* with Undo. Blocking problems (`blockingProblems`, `showBlocking`) are also shown **at the source**: red `aria-invalid` + inline helper under the title/type controls in the header (already partly done via `aria-invalid`; add text, e.g. `aria-describedby`). Text corrections are **removed from the panel list while they have a live inline anchor**, and shown there only if they can't be anchored (find not found) — so nothing is lost.

A tiny **status chip** near the Check button — "7 suggestions" with ◀ ▶ buttons — steps through inline suggestions (document order) and focuses the popover; this is the "review mode" the research recommends (counts + prev/next) without a heavy panel.

### 4.5 Error and empty states
- `analysisStatus === "error"`: non-blocking inline banner under the header (reuse `errorMessage(t, code)` — includes `analyzer_unavailable`); text stays editable; "Try again".
- No text: Check disabled with a hint; show "Insert example" (existing `handleInsertExample`) as an empty-editor affordance instead of in the panel.
- Loading: the editor remains editable during analysis (already true); suggestions apply only if `analyzedText` still matches when results arrive; otherwise show the stale chip.

---

## 5. Implementation plan (phases — each independently shippable, TDD)

**Phase 0 — Safety net.** Read `FreeTextWorkoutEditor.test*`/existing specs (`apps/web/src/lib/free-text-analysis.test.ts`, `e2e/quick-text-workout.spec.ts`) and add a Playwright test that opens the free-text page, types text, runs the (stubbed) analysis, accepts one text correction and publishes. This must stay green through every phase.

**Phase 1 — Declutter the page.** Split `FreeTextWorkoutEditor.tsx` (1000 lines) into: `FreeTextEditorHeader.tsx`, `FreeTextToolbar.tsx` (+ `ToolbarOverflowMenu.tsx`, `SelectionBubbleMenu.tsx`, `LinkPopover.tsx`), `FreeTimerPopover.tsx` (wraps `FreeTextTimerFields`), keep state in the editor component or a small hook `useFreeTextDraft`. Remove `CollapsibleRibbon` and `collapsedRibbons` state. Move Publish to the header, character count/stale chip to the footer. Add/rename i18n keys.

**Phase 2 — Toolbar.** Primary row + bubble menu + overflow, roving tabindex, `aria-pressed`, ≥ 44 px touch targets, inline link popover (no `window.prompt`). Unit/RTL tests for keyboard navigation; axe check (see `e2e/public-accessibility.spec.ts` for the axe setup).

**Phase 3 — Inline suggestions.** (a) `locateText` + `replaceRange` pure helpers with unit tests (single block, multiple marks in a block, missing text, formatting preserved, IME/empty, RTL text). (b) `inlineSuggestionsOf(review)` selector. (c) `AssistantSuggestions` extension + CSS. (d) `AssistantSuggestionPopover` + Floating UI + keyboard commands + live region. (e) Wire into `FreeTextWorkoutEditor`: ref to latest suggestions, `onSelect` state, accept/dismiss via existing handlers using the decoration range. (f) De-duplicate with the panel (§4.4).

**Phase 4 — Review panel slimming + prev/next chip + error/empty states.**

**Phase 5 — Docs & polish.** ADR-137, `docs/technical_debt.md` entries (multi-occurrence suggestions, per-rule "don't show again", bulk accept for high-confidence, async analysis), update any user-facing guide under `docs/guides/` if it mentions the editor.

### Acceptance criteria
1. At 1366×768 the editor text area starts within ~200 px of the top; title, type, Timer, Check and Publish are visible without scrolling or expanding anything.
2. Only one toolbar row by default; at most ~11 controls visible; all previously available formatting remains reachable (bubble menu or More).
3. After a check, every open `text_correction` whose `find` exists in the text is underlined; click, tap, `Mod-.` and prev/next all open the popover; Accept replaces exactly that range keeping surrounding formatting; Dismiss keeps the text; Undo (from Resolved list) still works; the review state saved in `draft_data.free_text_review` is unchanged in shape.
4. Editing a flagged phrase removes its underline immediately; typing is never blocked or reflowed by the popover.
5. Decorations never appear in saved `free_text_document` / `free_text_body`, in Preview, or in the athlete view.
6. Fully keyboard operable and screen-reader friendly (names, `aria-pressed`, live-region announcements, `Escape` returns focus); axe-core has no new violations; works with `prefers-reduced-motion` and forced-colors.
7. RTL (`ar`, `he`) renders correctly (logical CSS properties, Floating UI logical placement); mobile uses the bottom sheet.
8. `npm run lint`, `npm run test`, `npm run test:e2e`, and **`npm run i18n:check`** pass.

### Project rules the implementer must follow
- **i18n:** all copy through `next-intl` / `useUiTranslations`; new keys in `apps/web/messages/*.json` for **all 12 locales** (`en, el, ar, bg, de, es, fr, he, it, nl, pt-PT, ru`) — the repo has `scripts/validate-messages.mjs`, `check-untranslated-messages.mjs` and `check-hardcoded-ui-copy.mjs` (run `npm run i18n:check`). Reuse existing `WorkoutAssistant.*` and `editor*` keys where possible.
- **Never hand-edit** `apps/web/src/api/generated/schema.ts`.
- **Styling:** CSS variables/tokens already used on this page (`--bg --card --panel --dim --muted --text --primary --warning --danger --success`), logical properties (`ms-`, `me-`, `ps-`, `text-start`) for RTL.
- **TDD** (write the failing test first), commit test + implementation together, finish with a **LIVE TEST** in the browser (the page needs a draft: `/org/<slug>/admin/workouts/new?mode=free-text`). Use the sample text from the bug report (supersets: "Incline Bench Press…", "Peck deck", "banded deficit push ups").
- Commit message prefix per `AGENTS.md` conventions (`feat(web): …`).

## 6. Risks and open questions
- **Floating UI dependency:** confirm it resolves from TipTap's transitive deps; add it explicitly (`@floating-ui/dom`) rather than relying on hoisting.
- **Decoration vs. text structure:** `find` may span several marks (bold + plain) within one block — `locateText` must map by concatenated block text, as `replaceInEditor` does today; a cross-block `find` is not supported (same as today) → falls back to the panel.
- **Analysis latency/502:** unrelated but affects UX; keep status handling decoupled (see non-goals).
- **Keyboard shortcut choice** (`Mod-.`, `Alt-↑/↓` vs `F8`) can clash with OS/browser shortcuts — implementer should verify on Linux/macOS/Windows and document in the "Keyboard shortcuts" help.
- **Decision for the owner (low risk, default given):** whether to keep the aside open by default after the first check (default: open Review tab once, then remember the choice in `localStorage`).

## 7. Sources
- [NN/g — Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/)
- [WAI-ARIA APG — Toolbar pattern](https://www.w3.org/WAI/ARIA/apg/patterns/toolbar/)
- [Velt — Rich Text Editor UI design best practices](https://velt.dev/blog/rich-text-editor-ui-design-best-practices)
- [Genesys Spark — Rich Text Editor](https://spark.genesys.com/latest/components/forms-and-inputs/rich-text-editor/usage-XlHQCpoM)
- [HeroUI Pro — Rich Text Editor (TipTap-based bubble menu / link popover)](https://docs.heroui.pro/docs/react/components/rich-text-editor)
- [Tiptap — Bubble Menu](https://tiptap.dev/docs/editor/extensions/functionality/bubble-menu)
- [Tiptap — Customize how suggestions are displayed (decorations + popover)](https://tiptap.dev/docs/content-ai/capabilities/suggestion/features/display-suggestions)
- [ProseMirror discuss — Suggestions as decorations](https://discuss.prosemirror.net/t/suggestions-as-decorations/9027)
- [web.dev — Design AI user experiences](https://web.dev/learn/ai/ux-patterns)
- [arXiv 2601.10236 — Design patterns for preserving authorship in AI-assisted writing](https://arxiv.org/pdf/2601.10236)
- [Grammarly — grouped writing suggestions](https://www.grammarly.com/blog/product/grouped-writing-suggestions/) · [Grammarly Support — dismissing suggestions](https://support.grammarly.com/hc/en-us/articles/4412837103117-how-to-deactivate-suggestions-in-grammarly-for-windows-or-grammarly-for-mac)
- [PhiaUI — LanguageTools inline grammar popover](https://phia-ui.hexdocs.pm/PhiaUi.Components.Editor.LanguageTools.md)
- [ProWritingAid — underline colours](https://help.prowritingaid.com/article/367-what-does-each-underline-color-mean) · [Microsoft — customize underline colours](https://support.microsoft.com/kb/925597)
- [WProofreader — keyboard access to suggestions](https://docs.wproofreader.com/faq/technical/wproofreader/how-would-keyboard-users-be-able-to-access-the-spell-check-suggestions) · [W3C WCAG G194 — spell checking and suggestions](https://www.w3.org/WAI/WCAG22/Techniques/general/G194)
