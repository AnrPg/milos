# ADR-151: Filters and saved filters
Date: 2026-10-19
Status: Accepted

## Context
Several Phase 2 screens filter long lists (Box › Πρόγραμμα first, later Γύρω
μου, the feed and the journal). Members expect their last filters to follow
them across devices.

## Decision
`saved_filters(user_id, surface, kind, name, params, last_used_at)`: per surface
the last-used params are remembered server-side, and named filters can be
saved. The web uses one chip-row and sheet pattern driven by a per-surface
schema; Πρόγραμμα is the first surface (location, class type, coach, time,
spots, covered by my package).

## Rationale
Server-side memory works across phone and desktop; one pattern keeps every
filtered screen familiar.

## Alternatives Considered
Local storage only: lost on a new device.

## Consequences
Each new surface declares its schema and validates params server-side.
