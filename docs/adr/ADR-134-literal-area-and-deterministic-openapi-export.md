# ADR-134: BEAM Literal Area Root Cause and Deterministic OpenAPI Export
Date: 2026-10-13
Status: Accepted

## Context

TD-093 bundled two tooling problems.

1. **`literal_alloc` crashes.** Full `mix test` runs on the agent machine
   aborted with `literal_alloc: Cannot allocate … (of type "literal")`.
   Agents worked around it with `ELIXIR_ERL_OPTIONS="+fnu +MIscs 4096"`,
   which raises the literal super carrier from 1 GB to 4 GB. The crash was
   recorded as "environment-specific" (ADR-124 Implementation Notes) without
   a cause.
2. **Noisy generated-client diffs.** `mix milos.export_openapi` wrote the
   spec with `Jason.encode_to_iodata!(spec, pretty: true)`. Jason writes map
   keys in map iteration order:
   - Maps with more than 32 keys (`paths`, `components.schemas`) iterate in
     hash order. Adding one path or schema reshuffles unrelated entries.
   - Small maps with atom keys iterate in atom-table order (OTP 26+), which
     depends on load order.

   Every contract change therefore rewrote large parts of
   `apps/web/src/api/generated/openapi.json` and the `schema.ts` that
   openapi-typescript generates from it, in JSON order. Parallel branches
   conflicted on that churn.

## Decision

1. **The literal-area crash is a code issue, and the code fix already exists.**
   - OpenApiSpex's default `PersistentTermCache` re-runs
     `:persistent_term.put/2` with the whole spec the first time each
     controller action is validated.
   - Every put copies the value (about 23 MB for our spec) into the literal
     area. Replaced copies are released only after a global literal GC, so
     a cold test run with dozens of validated actions fills the 1 GB area.
   - `MilosTrainingWeb.OpenApiSpecCache` (configured in `config/config.exs`)
     stores the spec once and ignores later puts. With it, the full suite
     passes on VM defaults.
   - We keep it as the single cache adapter, delete the shadowed duplicate
     `MilosTrainingWeb.ApiSpecCache`, guard the behaviour with a test, and
     drop `+MIscs 4096` from the documented workflow (AGENTS.md).
2. **Deterministic export.** A new module, `MilosTrainingWeb.OpenApiExport.encode!/1`:
   - encodes the spec with the normal encoders, so OpenApiSpex's struct
     encoders still drop `nil`s;
   - decodes the result;
   - re-encodes it as nested `Jason.OrderedObject`s, with keys sorted by byte
     order and array order kept;
   - pretty-prints it with a trailing newline.

   The mix task uses this module. The generated files were regenerated once
   and only their ordering changed.

## Rationale

- Fixing the cache bounds literal-area use: 118 MB peak for the full
  suite (measured), against a 1 GB area. Raising `+MIscs` only moved the
  ceiling, and every developer, CI runner and agent had to remember the flag.
- The flag cannot be made a repository default for `mix test` anyway.
  Emulator flags are read when the VM boots, and the VM has already booted
  when Mix evaluates `mix.exs`, `config/*.exs` or an alias.
  `System.put_env("ELIXIR_ERL_OPTIONS", …)` in an alias is too late. The
  only options are a shell wrapper or a `.erlang`/`vm.args` file, and a wrapper
  just hides the leak.
- Sorting keys is the standard way to get stable, mergeable JSON. Encoding,
  decoding and re-encoding reuses every existing `Jason.Encoder` instead of
  re-implementing OpenApiSpex's encoding rules. Export is a dev-time task,
  so the extra pass does not matter. It needs no new dependency
  (`Jason.OrderedObject` is part of Jason 1.3+).
- Arrays keep their order, because order is meaningful for `required`,
  `enum`, `parameters`, `servers`, `oneOf` and similar fields.

## Alternatives Considered

- **Make `+MIscs 4096` the project default via a `bin/test` wrapper or
  `ERL_FLAGS` in CI.** Rejected. It treats the symptom, and the suite now
  passes without it. It stays documented as a diagnostic knob only.
- **Keep `ApiSpecCache` instead of `OpenApiSpecCache`.** `ApiSpecCache`
  precomputes the operation of every routed action, so later requests skip
  the per-request lookup insert. It was shadowed by the later `config`
  line, so the suite had only ever been validated with `OpenApiSpecCache`.
  The per-request cost of the latter is one `Map.put` on the operation
  lookup (no copy into the literal area), which is negligible. Two adapters
  for one job are confusing, so the unused one is removed.
- **Sort in the web toolchain (e.g. `jq -S` before openapi-typescript).**
  Rejected. It adds a tool dependency and leaves the exporter
  nondeterministic for other consumers.
- **Custom pretty-printer.** Rejected. `Jason.OrderedObject` already does
  this with `pretty: true`.

## Consequences

- Full backend runs work on VM defaults. Agent briefs and docs no longer
  need to prescribe `+MIscs 4096`. `+fnu` is unrelated, and agents may keep
  it alongside `LANG=C.UTF-8`.
- Going back to OpenApiSpex's default cache adapter, or re-putting large
  terms into `:persistent_term` elsewhere, can bring the crash back.
  `OpenApiSpecCacheTest` checks the adapter config and the store-once
  behaviour.
- The first regeneration under this ADR rewrites `openapi.json` and
  `schema.ts` once (pure reordering: the JSON is semantically identical, and
  `schema.ts` has the same multiset of lines). Later contract changes
  produce local hunks.
- Branches that regenerated the client before this change will conflict
  once on the generated files. Resolve by regenerating
  (`npm run generate:api`), not by hand-merging.

## Implementation Notes

- **Reproduction.**
  - Full suite with only `+fnu` and the current config: `1409 tests,
    0 failures` in 749.5 s. There was no crash, so the crash was not
    environmental on this machine.
  - With the default adapter temporarily restored
    (`config :open_api_spex, :cache_adapter,
    OpenApiSpex.Plug.PersistentTermCache` in `config/test.exs`), running
    `mix test test/milos_training_web` with only `+fnu` aborted after
    ~120 tests:
    `literal_alloc: Cannot allocate 25801304 bytes of memory (of type
    "literal")`, followed by an `erl_crash.dump`.
- **Measurements.** These come from a temporary `ExUnit.after_suite` probe,
  which was not committed.
  - Full suite (1416 tests, 0 failures, only `+fnu`) with
    `OpenApiSpecCache`: literal_alloc `mbcs.carriers_size` at 118 MB current
    and 118 MB max, against the 1 GB default. `persistent_term` holds 183
    terms (16.6 MB). The only large one is the cached spec, at about 22 MB
    as a flat term.
  - Web suite alone (353 tests): 101 MB peak.
  - Largest `.beam` files: `Schemas.Workout` at 2.6 MB, then
    `AdminFinanceController` at 0.7 MB and `Router` at 0.6 MB.
    `_build/test/lib/milos_training/ebin` totals 21 MB. Module literals are
    not the problem.
- **Dead code.** Both merged lines (multi-role and assistant) had
  independently fixed the cache. Their `config :open_api_spex,
  :cache_adapter` lines collided, and the later one (`OpenApiSpecCache`)
  won. ADR-098 still names `ApiSpecCache`. This ADR supersedes that detail.
- **Generated files.** The `openapi.json` diff is about 102k lines and the
  `schema.ts` diff about 38k lines. Both are reordering only. A Node check
  of the old and new JSON with keys canonicalised found them equal, and the
  sorted line hashes of the old and new `schema.ts` are equal.
- **Deviation.** The TDD order was test then implementation, but the
  failing-first run of `OpenApiExportTest` was skipped. It could only have
  failed with an undefined-module error.
