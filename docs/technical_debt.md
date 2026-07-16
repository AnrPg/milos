# Technical Debt Ledger

## Status Registry

The registry is authoritative for lifecycle state; the detailed ledger below retains
the original wording and dates for traceability.

| ID | Status |
|---|---|
| TD-001–TD-005 | Open |
| TD-006 | Resolved |
| TD-007–TD-008 | Open |
| TD-009 | Resolved |
| TD-010 | Open |
| TD-011 | In progress |
| TD-012–TD-013 | Open |
| TD-014–TD-015 | In progress |
| TD-016–TD-018 | Resolved |
| TD-019 | Open |
| TD-020 | Resolved |
| TD-021–TD-023 | Open |
| TD-024–TD-030 | Resolved |
| TD-031 | Open |

## Detailed Ledger

| ID | Phase | Description | Reason deferred | Priority | Added |
|---|---|---|---|---|---|
| TD-001 | Phase 0 | Stripe payment gateway integration | Manual-only in v1 per spec | Medium | 2026-06-05 |
| TD-002 | Phase 2 | Admin UI does not yet author nested sub-sections despite backend support for `parent_section_id` | Phase 2 shipped the flat linear editor first to keep the core creation/materialization flow stable | Medium | 2026-06-05 |
| TD-003 | Phase 2 | Workout canvas does not yet support desktop cross-section exercise drag-hover moves | Phase 2 shipped sortable sections, sortable in-section exercises, and explicit move-to-section controls first to keep the authoring flow stable | Medium | 2026-06-07 |
| TD-004 | Phase 3 | Schedule UI uses a custom responsive day-column calendar instead of `react-big-calendar` | Phase 3 avoided introducing an additional date-localizer dependency while shipping the booking and approval flow end-to-end | Medium | 2026-06-08 |
| TD-005 | Phase 3 | Admin cannot delete a slot that already has bookings; backend blocks deletion instead of offering a confirm-and-cancel/archive flow | Phase 3 chose safe non-destructive behavior first to avoid silently dropping booking history or member state | Medium | 2026-06-08 |
| TD-006 | Phase 7 | Landing-page membership card has no live data source yet and remains hidden unless membership fields are added in a later phase | Membership persistence and admin financial tooling have not been implemented yet, so Phase 7 could only ship the optional UI slot and read-model placeholder | Medium | 2026-06-09 |
| TD-007 | Phase 7 | `custom` seasonal challenges currently use a generic per-completion increment instead of a richer admin-defined progression model | Phase 7 prioritized the automatic challenge pipeline for workout-count, workout-type, and PR-based criteria first so the end-to-end gamification loop could ship without inventing a premature manual progression subsystem | Medium | 2026-06-09 |
| TD-030 | Phase 6 | Phase 7 gamification read/write modules are partially present in the repo before their schema rollout is complete, so workout-completion side effects currently degrade with a warning instead of executing full gamification updates | Phase 6 hardened the event handler to avoid crashing notification-adjacent flows, but the full gamification tables/materialized views still need to land as one coherent phase | High | 2026-06-09 |
| TD-008 | Phase 4 | HRR sections still cannot auto-measure true heart-rate-drop scores without external sensor input, so the execution fallback score uses elapsed time unless the athlete overrides it manually | Phase 4 now persists semantic progress and fallback scores across formats, but the current product has no live heart-rate device integration to supply a trustworthy `hr_drop` metric automatically | Medium | 2026-06-10 |
| TD-009 | Phase 8 | Resolved 2026-06-13 by ADR-025: signed per-user `.ics` feeds now expose webcal subscribe, HTTPS copy-link, and one-off download flows with per-platform help text | Kept in ledger for traceability of the calendar/iCal export gap | Low | 2026-06-10 |
| TD-010 | Phase 8 | Finance remains manually operated: scheduled renewal generation, payment reminders, invoice PDFs, and external payment collection are not implemented | Invoice, renewal, allocation, and entitlement rules now exist; delivery automation and payment-provider integration remain additive work | Medium | 2026-06-11 |
| TD-011 | Phase 8 | Analytics event capture is implemented for Phase 8 finance/reviews/injuries/notification read-click flows, but not yet comprehensively instrumented across workouts, classes, communication threads, workout abandonment, assignment opens, and broad notification push delivery outcomes | The audit identified many telemetry/data-capture dimensions; Phase 8B added the event pipeline and first write-boundary instrumentation, while broader legacy-domain instrumentation needs a separate hardening pass | High | 2026-06-11 |
| TD-012 | Phase 8 | Review questionnaires are persisted structurally but do not yet have an admin questionnaire builder or per-target default questionnaire selection | MVP supports freeform reviews and answer persistence first; questionnaire authoring can be layered on the `review_questionnaires` table later | Medium | 2026-06-11 |
| TD-013 | Phase 8 | Injury reporting stores status history and profile-linked reports, but workout prescription safety warnings and automatic analytics segmentation are not yet surfaced across all workout/class UIs | MVP adds the Wellbeing context and admin/user pages first; deeper workout editor/execution integration is deferred to the Phase 8 extension | High | 2026-06-11 |
| TD-014 | Phase 8 | Partially resolved 2026-06-13 by ADR-025: admin search now uses a Meilisearch member index with PostgreSQL fallback and live suggestion-compatible API metadata | Query-time index rebuild is MVP-safe but should become event/job-driven incremental indexing as more facets are stabilized | Medium | 2026-06-11 |
| TD-015 | Phase 8 | Partially resolved 2026-06-13 by ADR-025: assignment messages, schedule slot messages, and admin coaching notes now persist durable communication threads/messages and feed analytics counts | Response-latency analytics and full UI thread management remain additive follow-up work | Medium | 2026-06-11 |
| TD-016 | Phase 8 | Resolved 2026-06-12 by ADR-019: Finance now has append-only admin payment reversal and invoice-credit-restoration workflows, and allocated invoices can be voided after net allocations are reversed | Kept in ledger for traceability of the Phase 8 accounting hardening gap | Low | 2026-06-11 |
| TD-017 | Phase 8 | Resolved 2026-07-15 by ADR-040: versioned package contracts now enforce channels, capabilities, class visits and coaching touchpoints through a concurrency-safe allowance ledger; legacy profiles have idempotent dry-run/apply backfill and admins can grant or revoke audited per-user extensions | Kept in ledger for traceability of the entitlement enforcement gap | Low | 2026-06-12 |
| TD-018 | Cross-cutting | Resolved 2026-06-13 by ADR-029: durable workout-completion projections now run through an atomic Oban handoff, and the global PubSub database handler was removed | Kept in ledger for traceability of the asynchronous teardown and durability gap | Low | 2026-06-12 |
| TD-019 | Cross-cutting | Next.js currently brings a transitive PostCSS `<8.5.10` advisory (`GHSA-qx2v-qp2m-jg93`), reported as two moderate production vulnerabilities by npm audit | npm currently offers only `audit fix --force` with a breaking Next.js downgrade; wait for and apply a compatible patched Next.js/PostCSS release | Medium | 2026-06-12 |
| TD-020 | Phase 8 | Resolved 2026-06-13 by ADR-025: Scheduling now owns `class_attendance_records`, while Analytics attendance remains a projection/read compatibility table | Kept in ledger for traceability of the attendance ownership migration | Low | 2026-06-12 |
| TD-021 | Phase 8 | Phase 8 frontend API helpers still use handwritten `Record<string, unknown>` wrappers instead of generated operation types throughout Finance, Reviews, and Wellbeing | OpenAPI JSON and TypeScript schemas are regenerated, but replacing the handwritten clients touches many admin screens and should be done as a focused contract-client migration | Medium | 2026-06-12 |
| TD-022 | Phase 8 | Finance refund/reversal workflows do not yet generate refund receipts, external payment-provider reconciliation records, or accounting-export artifacts | The MVP is still manual-payment first; provider and accounting integrations should attach to the append-only reversal facts without changing the core schema | Medium | 2026-06-12 |
| TD-023 | Cross-cutting | Notification semantic types are still duplicated across database constraints, Ecto enums, dispatchers, push message builders, and frontend rendering | ADR-032 aligned the `workout_moved` type, but a generated or shared notification-type contract should replace manual synchronization | Medium | 2026-06-13 |
| TD-024 | Admin App Configurations | Resolved 2026-07-15 by ADR-037: Scheduling owns configurable class types with admin create/rename/archive, required explicit slot classification, and historicity-preserving future-class remapping. | Kept for traceability of the fixed class taxonomy gap. | Low | 2026-07-15 |
| TD-025 | Class Schedule | Resolved 2026-07-15 by ADR-037: desktop/tablet filters are compact non-wrapping multi-select controls; mobile uses an apply/clear multi-choice disclosure. | Kept for traceability of responsive taxonomy filtering. | Low | 2026-07-15 |
| TD-026 | Class Schedule | Resolved 2026-07-15: class scheduling and coaching assignments share the same responsive `ViewModeSelector` for 3-day, 7-day, and month modes. | Kept for traceability of calendar-control inconsistency. | Low | 2026-07-15 |
| TD-027 | Personal Coaching / Workout Assignment | Resolved 2026-07-15 by ADR-039: quick assignment embeds the existing draft/autosave/publish canvas and immediately selects the published library workout without navigation. | Kept for traceability of assignment context switching. | Low | 2026-07-15 |
| TD-028 | Admin Dashboard | Resolved 2026-07-15 by ADR-038: operational heroes are compact and collapse after three seconds with a reveal control (homepage excepted); dashboard logout was removed and KPIs use a circular control-panel treatment. | Kept for traceability of persistent hero density. | Low | 2026-07-15 |
| TD-029 | Notifications / Browser Push | Resolved 2026-07-15 by ADR-038: non-cacheable server capability is refreshed each session/panel open, missing setup has role-aware guidance, and users enable/disable subscriptions per browser/device. | Kept for traceability of stale and non-actionable push capability UI. | Low | 2026-07-15 |
| TD-031 | Observability | Provision production dashboards and alert thresholds for the emitted OTLP traces, structured telemetry summaries, readiness failures, outbox age, auth anomalies, cache invalidation, upload rejections, and Oban failures | The application now emits the required signals and can export traces, but concrete dashboards/alert destinations depend on the owner's collector/monitoring stack | High | 2026-07-16 |
