# ADR-108: Static Page Headers and Client-side Users Directory
Date: 2026-10-12
Status: Accepted

## Context
Pages opened with a large introduction banner (`TransientHero`) that collapsed
after a timeout and re-expanded on hover, shifting layout and hiding actions.
The users directory was a flat list with server-side role filtering only.

## Decision
- Replace `TransientHero` with a static `PageHeader`: the page title plus any
  actions the banner carried.
- The users directory loads the tenant directory once (paged, capped at 1,000)
  and filters client-side: accent-insensitive search with a `/` shortcut, role
  tabs with live counts, membership-status filter, sorting, URL-synced filters,
  responsive table/cards, skeleton loading, retry and actionable empty states
  with an Invite CTA.

## Rationale
Predictable headers remove layout shift and hidden controls. Gyms have tens to
hundreds of clients, so one fetch makes search and counts instant.

## Consequences
Very large tenants need server-side search, counts and sorting (TD-060).

## Implementation Notes
None beyond the above.
