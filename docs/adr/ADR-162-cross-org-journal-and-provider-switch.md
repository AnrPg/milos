# ADR-162: One journal across providers and the Box ▾ provider switch
Date: 2026-10-21
Status: Accepted (board 17 answered: A on all six, plus Εξαγωγή)

## Context
Plan §5 P2-M14, ADR-150 and ADR-151 (Phase 2), and vision §7.10. A member
can train with a gym and an independent coach at the same time; an
independent coach is a one-person organization. Box shows everyone who
trains you, and the title ▾ switches between them. Today's card merges
items from all of them with source labels, and there is **one journal**.
The engineering gap: PRs and injuries were account-scoped, but the
training log, Πρόοδος, history and the coach's view were org-scoped. The
journal feed (ADR-139) already read the member's own rows across
organizations in their personal session, and coaches read through
`{:coach, organization_id}` and `milos_entry_visible_to_acting_coach`.

## Decision
1. **Providers.** `organizations.provider_kind` (`gym` | `coach`) and
   `organization_memberships.ended_at`, which a trigger sets when a
   membership leaves `active` (suspended, revoked) and clears when it
   returns. That way the end date is right whichever code path changed the
   status. `milos_my_providers()` is a definer lookup that answers only the
   caller's own memberships of any status, with name, kind, brand, status
   and end date. A former provider's `organizations` row is invisible to
   the member's session, yet every view still labels its entries.
   `Organizations.Domain.Provider` splits them into active and former and
   picks the provider Box opens on. That choice is remembered in
   `account_provider_selections`.
   - `GET /api/me/providers` lists each active provider with its kind,
     logo, next class or appointment (30 days ahead) and unread messages.
     These facts are read in that provider's tenant context with the
     member's own authorization. If one provider fails, that provider is
     marked `partial` and the rest of the list still loads. Former
     providers come back as `former` with `ended_at`.
   - `PUT /api/me/providers/selected` remembers the choice and accepts only
     an active provider.
2. **Today across providers.** `GET /api/me/today?date&timezone` asks each
   active provider through `Ports.ProviderToday`. The default port lists
   the day's booked classes, appointments, the coach's programme for the
   day and the WOD; it leaves the WOD out when a booked class already
   shows it. Each provider is computed in its own tenant context.
   `ProviderToday.merge/1` orders the items, untimed first. A failing
   provider is skipped and named in `failed_organization_ids`, and the
   card is marked `partial`. Every item carries its `source` and the
   `target` (organization id and slug) to switch to.
3. **Account read model** (ADR-150), built by `AccountTraining` in the
   member's personal session:
   - `GET /api/me/history` (`workouts` | `classes`, offset paging,
     `sources`, dates). A booking is the provider's record of the member's
     own visit, so classes are read in each provider's system scope. This
     also covers former providers: the history stays the member's.
   - `GET /api/me/progress` returns the same sections as the per-provider
     page (`ProgressStats`) plus `by_source`. Score history is grouped by
     canonical workout identity and section name, so one benchmark done at
     two providers is one line. Points and PRs carry their source.
     `ProgressFilter` adds `range` (4w, 12w, 6m, 1y, all), `sources` and
     `exercise`. The per-provider endpoint keeps its package gate
     (ADR-098). The account view is the member's own data and is not gated,
     like PRs.
   - `GET /api/me/vault` groups completed executions and logged entries by
     `WorkoutIdentity`, first match wins:
     1. a `benchmark:<slug>` tag, or a title that normalises to a known
        benchmark;
     2. the library workout it was copied from;
     3. the normalised title plus discipline.
     Every attempt carries its source. `VaultFilter` adds disciplines,
     benchmark, exercise, sources and dates. `/api/executions/vault` and
     the org-scoped `/me/progress` and `/me/history` endpoints are
     unchanged.
4. **Entry sources.** `EntrySource` labels each entry as one of:
   - `organization`, with name and `former`;
   - `device` (Garmin, Apple Health or Health Connect, recognised by a
     training-log `source_type` or a wellness `source`; M13 plugs in
     without changes here);
   - `freeform`, meaning no provider.
   Every item in the member's Ροή, history, Vault and Πρόοδος carries one.
5. **Ροή filter** (ADR-151). `JournalFilter` v1 holds `kinds`, `sources`,
   `visibilities`, `date_from` / `date_to` and `q`. It is pure and
   versioned, and it is shared by `GET /api/me/journal`, the remembered
   last-used filter (`remember=true`, or `PUT /api/me/filters/journal/…`)
   and named saved filters. The journal, Vault and Πρόοδος surfaces now
   store normalised params. `FeedScope` applies the filter in SQL to every
   source: the source predicate, rungs, a date window, and text. Text is
   matched with `ILIKE` on the entry's own text and its Σχόλια, under new
   `pg_trgm` GIN indexes. Kinds without text drop out while `q` is set.
6. **«Οι coach μου» across providers** (board 17, Q5).
   `Journal.Domain.CoachAudience` is the single policy:
   - Only rungs that reach a coach count. Injuries and reviews always go
     to their home provider.
   - Only providers the member is an **active** member of can read.
   - The home provider always reads, on a coach rung.
   - Anyone else reads only when the entry is shared with them, either
     through the entry's own audience (`journal_entry_audiences`), or,
     for a provider-less entry, through the member's default audience.
     The default is every active provider minus
     `journal_coach_audience_exclusions`, so a new provider is included by
     default.
   Freeform and device entries start private. A provider-less entry can
   move to `coach_can_view` once it has an audience. A reply request still
   needs the entry's own gym. Shareable kinds: execution, training_log, pr,
   note and check_in.
   - The SQL twin is `milos_journal_entry_shared_with_org`. It is used by
     `FeedScope`'s coach scope and by additive `…_coach_shared_read_policy`
     row policies on `journal_notes`, `wellbeing_check_ins`,
     `user_pr_records`, `workout_executions` and `training_log_entries`.
   - Endpoints: `GET|PUT /api/me/journal/coach-audience`,
     `PUT /api/me/journal/entries/:kind/:id/audience`, and an optional
     `audience` on the visibility move. Feed items carry `audience`
     (`custom` and the providers a coach rung reaches).
7. **Leaving a provider** (Q6). Entries stay in every view of the member,
   labelled `former: true`. The provider loses access to all of the
   member's entries from the end date in three places:
   - the coach read path refuses a member without an active membership;
   - both row-security functions require one;
   - Box ▾ moves the provider to `former`.
   The provider keeps its own business records (bookings, attendance).
8. **Export** (board extra). `POST /api/me/journal/export` records a
   pending export, at most one at a time. `JournalExportJob` builds
   `journal.json` (every entry with its source) and `training.csv`, stores
   them under `users/<id>/exports/journal/<id>/` in private storage, and
   sends `journal_export_ready`, translated into all 12 locales.
   `GET /api/me/journal/exports` gives short-lived download links for
   seven days, after which the export reads `expired`.

## Rationale
- The account read model reads in the member's own session, under the same
  RLS predicate as the journal feed. Provider-specific facts (bookings,
  WOD, messages) are read in each provider's tenant context, so no context
  reaches into another's tables and authorization stays per provider.
- Audiences are stored per provider, not per coach. A provider's coaches
  share a reply queue and their coaching relationships change. Storing
  exclusions keeps «all my active coaches» the default as providers come
  and go.
- One pure policy module with a SQL twin, tested as an exhaustive matrix,
  keeps the coach path, the member's feed and row security from drifting
  apart.

## Alternatives Considered
- **One journal per provider** (board option B): it splits one person's
  history.
- **Every provider sees everything shared** (Q5 option B): it leaks a
  private coach's programme to the gym.
- **Per-coach audiences**: deferred. Coach-level granularity can be added
  later with a `coach_user_id` column, without changing the policy's shape.
- **Postgres full-text search** for Ροή: trigram `ILIKE` handles Greek and
  partial words without a language configuration.

## Consequences
- Org-scoped endpoints remain for per-provider screens. The web moves
  Ημερολόγιο, Vault, Πρόοδος and Box ▾ to the account endpoints.
- `provider_kind` defaults to `gym`. An owner setting to mark an
  independent coach is a follow-up.
- A rejoined member's earlier entries become visible to the provider again,
  under the same rules.

## Implementation Notes
- Migration `20261105100000_cross_org_journal`. Its timestamp sorts after
  the parallel M12 and M13 migrations.
- `Visibility.validate_move/3` takes a reach (`:gym`, `:audience`, `:none`).
  A boolean still means gym or none.
- The ADR-139 journal test now expects that a personal note can go to the
  member's coaches.
- Web (board 17, all recommended): `apiRequest` takes `scope: "account"` so
  `/me/history` and `/me/progress` reach the account read model instead of
  their per-gym paths. Box ▾ (`ProviderTitle`, `ProviderSheet`) switches via
  `PUT /me/providers/selected`, then remembers the slug on the device and
  clears the per-gym cache; a device without a remembered gym adopts the
  account's choice. The merged «Σήμερα» card shows only with two or more
  providers. Source labels show once there is more than one provider, and
  always for freeform, device and past-provider entries.
- The Ροή, Vault and Πρόοδος filters share `useRememberedFilter` (ADR-151).
  Ροή stores its filter through `remember=true` on the feed, the others
  through `PUT /me/filters/:surface/last-used`.
- «Οι coach μου» is asked in the visibility picker the first time a coach
  rung is chosen with several providers (once per device). The default can
  also be changed in Ρυθμίσεις, next to «Εξαγωγή ημερολογίου».

