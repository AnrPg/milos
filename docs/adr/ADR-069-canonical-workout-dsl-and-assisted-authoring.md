# ADR-069: Canonical Workout DSL and Assisted Authoring
Date: 2026-07-31
Status: Accepted

## Context

Workout authoring currently uses one structured canvas backed by durable
`draft_data` and an explicit publish/materialization boundary. Coaches also
need a faster document-like authoring mode without introducing a second
published workout model or relying on ambiguous natural-language inference.

The text mode must express the complete canonical workout model, including all
section formats, headers, notes, concrete per-set prescriptions, progressive
loading and deloading, groups, scale variations, score settings, and timers.
It must also be practical for non-technical coaches through contextual
autocomplete, templates, live diagnostics, and canonical beautification.

The existing format vocabulary is already consumed by authoring, validation,
execution, and frontend presentation. Hand-maintaining another independent
format or keyword list would create drift. The current worktree also contains
the additive structured-set implementation from ADR-068, which this decision
must preserve.

## Decision

Add a versioned, deterministic, line-oriented workout DSL as a second
authoring interface over the existing canonical workout draft.

The structured canvas remains the reference editor and the published
canonical workout remains the sole source of truth. Quick Text source is a
recoverable draft artifact; publication always reparses and validates it on
the backend before using the existing Workouts publish/materialization path.

Implement the authoritative lexer/parser, canonicalizer, validator, and
formatter as pure Elixir domain modules within `MilosTraining.Workouts.Domain`.
The parser returns canonical draft maps plus structured, source-positioned
diagnostics. It does not access Ecto, Phoenix, HTTP, search infrastructure, or
the exercise database.

Use a shared pure domain vocabulary registry as the source for parser tokens,
formatter ordering, required format fields, help metadata, and frontend
autocomplete data. `TimerConfig` delegates its supported-format and
required/optional-field knowledge to this registry rather than retaining a
second list.

Use Tiptap for the Quick Text browser editor. It presents a familiar
word-processor surface while allowing semantic workout nodes and contextual
suggestion extensions. Canonical DSL text is the parseable Quick Text draft
source. Tiptap JSON may be retained as a presentation cache with a source hash,
but it is never an independently authoritative workout representation.

Autocomplete has two explicitly separated sources:

1. canonical structural vocabulary, format-specific parameters, enums, units,
   active scale levels, and exercise suggestions;
2. non-semantic common workout/general words for titles, subtitles, and notes.

Only canonical suggestions create workout semantics. Common-word suggestions
never silently create parameters or change the canonical model. Suggestions
are local/cached and continuously narrowed as the user types; no third-party
cloud writing service receives draft content.

The first implementation slice establishes the registry, parser,
canonicalizer, formatter, conformance tests, and parse/preview boundary before
the full Tiptap surface. Subsequent slices add the editor, autocomplete
providers, complete format templates, and the coach manual against the same
registry and fixtures.

## Rationale

One canonical model preserves existing materialization, assignment, execution,
history, and modification-patch semantics. A deterministic grammar converts
author convenience into certainty: invalid or ambiguous source is saved as a
draft but cannot be published.

An authoritative backend parser prevents client behavior from becoming a
publication trust boundary. Keeping parsing and formatting pure follows the
hexagonal architecture and makes exhaustive unit and property testing
possible.

A shared vocabulary registry prevents the format discrepancy already found
between early product prose and the current nineteen backend formats.
Contextual completion and snippets let strict syntax remain usable by coaches
without requiring them to memorize a programming language.

Tiptap is schema-driven, extensible, and capable of conventional rich-text
interaction. Using it only at the interface layer keeps the domain independent
of the editor dependency.

## Alternatives Considered

Parsing arbitrary natural language, with or without an LLM, was rejected
because publication meaning would be probabilistic and ambiguous.

Maintaining text workouts as a separate aggregate was rejected because
structured and text authoring would diverge and every downstream consumer
would need two models.

Treating Tiptap JSON as the canonical workout was rejected because editor
presentation nodes are not the domain contract and would couple backend
business rules to one browser library.

Implementing the authoritative parser only in TypeScript was rejected because
the client is untrusted and publication must remain correct for every client.

Duplicating a complete parser in Elixir and TypeScript by hand was rejected
because grammar and diagnostics would drift. The frontend may perform
lightweight incremental token/context analysis for immediate assistance, but
the backend result is authoritative and both sides consume the same vocabulary
and conformance fixtures.

Using Meilisearch or a cloud service for every keystroke was rejected because
canonical completion must be immediate, private, and usable offline.

## Consequences

The Workouts context gains a stable DSL/version contract and pure domain
modules. Grammar changes require versioning, conformance fixtures, formatter
updates, autocomplete updates, and documentation updates.

Draft payloads may carry authoring mode, DSL source, and an optional editor
document cache without a new database table because `draft_data` already owns
incomplete authoring state. Published workout tables remain canonical.

New parse/preview endpoints, if introduced, must be specified in OpenAPI before
controllers. They call Workouts public APIs or an application service and
never call domain modules directly from controllers.

Tiptap and its selected extensions are approved new frontend dependencies for
this feature. Their bundle size, sanitization behavior, accessibility, and
license must be verified during implementation.

Exercise names are currently authored strings rather than references to a
dedicated exercise-catalog entity. Initial autocomplete can use curated and
previously authored names, but stable exercise IDs require a separate
canonical exercise-catalog design and additive schema change before they can
be guaranteed.

Invalid Quick Text remains autosavable. Preview, mode conversion to Structured,
and publication require a valid canonical result.

## Implementation Notes

The first vertical slice was implemented on 2026-07-31:

- `MilosTraining.Workouts.Domain.WorkoutDsl` now provides a deterministic
  line-oriented parser and canonical formatter with positioned diagnostics.
  It supports workout and section metadata, the nineteen canonical section
  formats, exercise/header blocks, notes, uniform prescriptions, explicit
  per-set load progressions and deloads, tempo, rest, and interval assignment.
- `WorkoutDsl.Vocabulary` is the shared backend registry for format names,
  timer parameters, DSL tokens, and contextual completion metadata.
  `TimerConfig` delegates its duplicated format registry to this module.
- The admin-only `POST /api/admin/workouts/dsl/parse` OpenAPI operation calls
  an Application service through the Workouts public API. It returns the
  canonical preview, formatted source, vocabulary, or source-positioned
  diagnostics.
- Draft payloads retain `authoring_mode`, `dsl_version`, `dsl_source`, and the
  optional Tiptap document. No published-workout schema or table was added.
- The workout creation screen now offers Structured and Quick Text modes.
  Quick Text uses Tiptap with conventional formatting controls, draft
  autosave, debounced authoritative parsing, canonical preview, Beautify,
  contextual completion, and conversion into the existing structured draft.
- Canonical tokens and formats are supplied by the backend preview vocabulary.
  The initial exercise-name and prose dictionaries are local curated lists;
  they do not create semantics and do not send workout text to third parties.

Verification completed with 22 isolated domain/application tests, 3
controller integration tests against PostgreSQL, 4 frontend suggestion tests,
TypeScript, ESLint, localization parity/hard-coded-copy checks, OpenAPI client
generation, compilation with warnings as errors, and
`mix milos.architecture`. A Playwright Chromium flow also exercised loading a
Quick Text draft, editing, authoritative preview, Beautify, autosave, and
conversion to Structured mode.

This slice deliberately does not claim the entire grammar manual. Full
format-specific templates, all nested/section/workout tweak combinations,
stable exercise-catalog IDs, richer localized diagnostic messages, direct
Quick Text publication through the existing canonical publish path, and
generated coach documentation/conformance fixtures remain follow-up work
tracked as TD-036.
