# ADR-039: Embedded Workout Authoring
Date: 2026-07-15
Status: Accepted

## Context
An administrator assigning a personal workout may discover that the needed
workout does not exist yet. Leaving the assignment modal loses context, while a
second assignment-only authoring model would duplicate validation, autosave,
publishing, and materialization behavior.

## Decision
The personal-coaching assignment flow embeds the existing workout creation
canvas. It creates the same durable draft, uses the same autosave and publish
endpoints, and publishes into the shared workout library. The canvas reports
the published workout to its host, which selects it without navigation.

Closing the embedded canvas does not delete its server draft. The draft remains
recoverable from the normal workout library.

## Rationale
One authoring workflow keeps workout validation and persistence consistent
regardless of entry point. Returning the published record through a component
callback preserves assignment state without coupling the API to a UI-specific
concept.

## Alternatives Considered
An assignment-only inline form was rejected because it would produce a reduced
workout model and duplicate write logic.

Opening the normal authoring route in another page or tab was rejected because
it breaks the focused assignment flow and needs cross-window synchronization.

Deleting a draft when the canvas closes was rejected because closing can be
accidental and drafts are intentionally recoverable work.

## Consequences
The creation canvas and header support embedded navigation callbacks while
retaining their standalone behavior. The Zustand editor state is reset at
embedded session boundaries, but the server remains the durable draft owner.

## Implementation Notes
`WorkoutCreationCanvas` accepts embedded, cancel, and published callbacks.
`CanvasHeader` returns the published `WorkoutRecord` to its host when supplied,
and otherwise preserves the standalone redirect. `QuickAssignModal` opens the
full canvas above the assignment dialog, selects the returned workout, and keeps
the athlete/date/note assignment state intact.
