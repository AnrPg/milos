# ADR-077: Free-text Exercises and Continuous DSL Completion
Date: 2026-08-02
Status: Accepted

## Context

Quick Text authoring currently treats the code-backed exercise catalog as a
publication constraint. Unknown labels fail parsing, aliases are rewritten to
canonical labels with a warning, and catalog capability metadata can reject an
otherwise valid exercise prescription. This conflicts with the product model:
exercise names are coach-authored free text and the catalog exists only to make
authoring faster.

The existing completion list is also rendered at the bottom of the editor and
only performs prefix matching. It does not provide the cursor-local,
always-available guidance needed for a custom DSL.

## Decision

Exercise labels in Quick Text are authoritative free text. Parsing preserves
the label exactly as authored and never emits unknown, ambiguous, alias, or
catalog-capability diagnostics. An exact canonical or alias match may retain a
stable `exercise_ref` as optional metadata, but it does not change the label or
the accepted prescription.

The browser editor continuously derives completion candidates from the local
DSL vocabulary and exercise catalog. It renders a keyboard-accessible menu at
the caret, provides context-specific keys on an empty line, and uses ranked
prefix, word, substring, and typo-tolerant matching for exercise labels and
aliases. Completion does not call a remote service per keystroke.

The singular exercise key `set` is accepted as an input alias for canonical
`sets`; formatting continues to emit `sets`.

## Rationale

Free-text labels let coaches describe movements in their own terminology while
the optional catalog still improves discovery and can enrich exact matches.
Keeping completion local makes it immediate, private, and available offline.
Canonical formatting of aliases prevents the convenience spelling from
creating a second output dialect.

## Alternatives Considered

Using Meilisearch for every keystroke was rejected because the vocabulary and
catalog are already delivered locally and completion must remain responsive
offline.

Keeping catalog warnings while allowing publication was rejected because the
warnings add noise without an action the coach is required to take.

Requiring only `sets` was rejected because the singular spelling is natural,
unambiguous inside an exercise or scale block, and easy to canonicalize.

## Consequences

The catalog is no longer a validation boundary. Catalog capability declarations
guide suggestions and documentation only; DSL syntax and value validation
remain authoritative.

ADR-070 is superseded only where it requires exact catalog resolution and
catalog capability enforcement for publication. Its additive metadata and
stable-reference decisions remain accepted.

## Implementation Notes

Implemented on 2026-08-02. The parser now preserves canonical, alias-like, and
unknown exercise labels verbatim; exact catalog matches may retain their stable
reference, but catalog resolution and capability metadata no longer emit
diagnostics or constrain publication. `set` canonicalizes to `sets`, and the
formatter continues to emit the plural form.

The local completion engine now infers the current block, offers valid keys on
fresh lines, and ranks exercise labels and aliases with prefix, word, substring,
subsequence, and edit-distance matching. The editor renders the menu beside the
caret, flips it above when necessary, repositions it during scrolling, keeps it
inside mobile viewports, and supports mouse, arrow-key, Enter/Tab, and Escape
interaction.

Verification covered 37 Workouts domain tests, all 107 frontend tests, focused
ESLint, TypeScript, and the Next.js production build. Live Chromium checks at
1440px and 390px confirmed typo completion for `sqt snach`, keyboard acceptance,
successful parsing and preview of `set: 3`, preservation of `Squat Snatch`, and
an arbitrary `My Odd Carry` label without exercise diagnostics. No follow-up
technical debt was deferred.
