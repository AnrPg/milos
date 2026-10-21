# ADR-174: AI scaling suggestions with mandatory coach approval
Date: 2026-10-21
Status: Accepted

## Context
Phase 3 milestone P3-M12 (plan `docs/plans/redesign-phase-3-depth.md`, brief §8.6) asks for AI help scaling a
programmed workout for an athlete with an injury the gym knows about. The same pieces were already in place:
- injury warnings for a movement (ADR-124 `InjuryRiskPolicy`);
- the gym's scale levels (ADR-128);
- workout modifications as patches (ADR-050);
- AI usage metering (ADR-152, the `[:milos, :ai, :generation]` event recorded by `RecordAiUsage`).

There was no per-gym provider key. The ethics checklist says an AI suggestion must never reach an athlete without a
coach's approval.

## Decision
- **Port and adapter.** `Scaling.Ports.ScalingAdvisor` takes `suggest(input, options)`.
  - The adapter is `Infrastructure.AI.AnthropicScalingAdvisor`, which calls the Claude Messages API over Req.
  - It asks for a JSON-schema structured output at effort `low`.
  - Default model `claude-sonnet-5-5`. It can be changed per gym in settings, or platform-wide with
    `ANTHROPIC_SCALING_MODEL`.
  - Errors are closed: `advisor_not_configured`, `key_rejected`, `unavailable`, `refused`, `invalid_response`.
  - Tests use a fake behind the port. The adapter itself is tested with `Req.Test`.
- **Per-gym key, inside AiUsage.** A new table, `organization_ai_settings`, holds:
  - the gym's own key, encrypted with `EncryptedBinary` and never returned by the API (only its last 4 characters);
  - the key status: unknown, valid or rejected;
  - an optional model;
  - `scaling_enabled`, which is **off by default**.
  It lives in the AiUsage context next to the existing meter. There is no second key store, no second meter and no
  platform key fallback.
- **When the advisor runs.** An hourly Oban scan looks at assigned workouts from today to day +2, only in gyms whose
  setting is ready. The advisor is called for an athlete and workout pair only if all of these hold:
  - the deterministic ADR-124 policy flags at least one movement against an injury the **gym** recorded (personal
    injuries are never used);
  - the inputs changed since the last suggestion, which a sha256 digest checks.
  Approved or dismissed suggestions are never regenerated.
- **What is sent.** The advisor receives:
  - the workout: sections and movements with their prescriptions;
  - the active injuries: body area, severity, tags and limitations;
  - the flagged movements;
  - the gym's scale levels;
  - up to 5 changes this coach approved before.
  It never receives names, user ids or injury ids.
- **How the answer is checked.** It is normalised against the real movement ids:
  - unknown ids are dropped;
  - at most one change per movement, and at most 12 changes;
  - a scale level is kept only if it is one of the gym's own levels.
- **Approval queue.** `GET /api/staff/scaling-suggestions`, `POST …/:id/approve` and `POST …/:id/dismiss`
  (`:manage_coaching`).
  - The queue holds only athletes the coach both coaches and may read health data for.
  - The coach can untick changes, rewrite a suggestion, drop the scale level and add a note.
  - Approval turns the kept changes into ADR-050 patches. Each patch is checked by `Execution.normalize_modification`
    and stored as `modifications` on the suggestion.
- **Member.** `GET /api/me/workouts/:workout_id/scaling` returns the approved adaptation only (otherwise `null`). An
  unapproved suggestion has no path to a member.
- **Metering.** Every call reports agent `scaling` and provider `anthropic` through the ADR-152 event, with cost from
  `PriceList`. The settings screen shows this month's count and cost.
- **Admin.** `GET/PUT /api/admin/ai-settings` (`:manage_settings`).

## Rationale
- Running the advisor only on a deterministic flag keeps cost and noise near zero: most athletes never trigger a
  call.
- Storing the approved changes as patches reuses the modification model. Nothing new is invented for "what changed".
- The gym pays for its own usage with its own key. That makes the feature an explicit opt-in, keeps the platform out
  of the billing path and fails closed when the key is missing or rejected.

## Alternatives Considered
- **One platform key with per-gym metering:** rejected. The platform would carry the cost and the data-processing
  role for every gym, and opting in would be implicit.
- **Generating on demand when the coach opens the queue:** rejected. The coach would wait 10–30 s, and the queue
  would look empty until then.
- **Applying approved changes directly to the athlete's assignment:** rejected for now. It would edit the coach's
  programme in place. The patches are stored and shown, and pre-filling the log from them is a follow-up.
- **Sending every athlete's workout:** rejected. It costs more and sends data the advisor does not need.

## Consequences
- Each gym needs its own provider key. Without one the feature stays off.
- Suggestions are made at most 2 days ahead. A workout assigned on the day is picked up by the next hourly scan.
- When the provider rejects the key, `key_status` is set to `rejected`, which stops generation until a new key is
  saved. The settings screen tells the owner.
- Follow-up: pre-fill the execution log from the approved patches, and add a coach notification for new suggestions.

## Decisions
Made without a board, at the owner's instruction (least clutter, robustness):
1. **Key in AiUsage, encrypted and write-only:** it reuses the existing context and cipher, so there is no second
   store.
2. **Off by default, and the switch needs a key:** this makes the opt-in explicit. Removing the key also switches the
   feature off.
3. **No platform key fallback:** fail closed, so the gym always knows who pays.
4. **Model configurable per gym, default `claude-sonnet-5-5`:** a good balance of quality and cost for short
   structured output. The owner can change it.
5. **Effort `low` with JSON-schema output:** the task is short and structured, and the schema removes parsing
   failures.
6. **Server-side fallback on refusal is enabled for the supported models:** a refusal still maps to `refused`, which
   the job cancels.
7. **Advisor only when ADR-124 flags a movement:** this saves cost, and the coach sees suggestions only where a
   warning exists.
8. **Gym-recorded injuries only:** the member's personal injuries stay private to them (ADR-124 provenance).
9. **No identities in the prompt:** data minimisation. The digest and the history carry no ids.
10. **Window today to day +2, hourly scan:** enough time for the coach to review, without generating weeks ahead.
11. **Digest de-duplication; approved and dismissed suggestions are never regenerated:** the coach's decision stands
    and the same question is never paid for twice.
12. **A new suggestion replaces a pending one when the inputs change:** the old row is kept as `superseded` for audit.
13. **Queue only for clients the coach coaches and may read health data for:** the same scope as injury warnings.
14. **The queue card appears only when something is waiting:** an empty card for every coach in gyms with the
    feature off would be clutter. It is one extension point under «Πελάτες μου».
15. **Edits limited to untick, rewrite, drop level and note:** these cover the real cases without building a second
    workout editor.
16. **Approval stores ADR-050 patches on the suggestion:** it reuses the modification model and leaves the programme
    itself untouched.
17. **The member sees one card, «Προσαρμογή από τον coach», under the injury warnings:** with no approved
    suggestion nothing is shown, not even a hint.
18. **AI disclosure on the member's card («Με βοήθεια AI · εγκρίθηκε από τον coach σου»):** transparency (vision
    §8.6).
19. **Reasons are neutral, with no medical claims:** the system prompt forbids diagnosis and medical advice.
20. **Settings in a collapsed «Βοηθός AI» section:** it is rarely changed, so it stays out of the way.
21. **Usage shown as this month's count and cost:** the owner sees what the key costs without opening a report.
22. **Migration `20261118100000`:** inside the range assigned to this milestone.

## Implementation Notes
- API files:
  - `apps/api/lib/milos_training/scaling/` holds the domain, ports, store and schema;
  - `application/scaling_suggestions.ex`, `application/gym_ai_settings.ex`;
  - `infrastructure/scaling/ecto_scaling_store.ex`, `infrastructure/ai/anthropic_scaling_advisor.ex`;
  - the workers `ScalingSuggestionScanJob` (cron `27 * * * *`) and `GenerateScalingSuggestionJob` (unique per pair).
- Both tables have RLS (ENABLE + FORCE, a tenant policy and the tenant trigger), are listed in `Tenancy.Audit`, and
  take part in tenant purge and export.
- `PriceList` gains `claude-sonnet-5-5`, `claude-opus-5-5` and `claude-haiku-5-5`. `TokenUsage.from_anthropic/1`
  bills cache writes as input.
- Web files:
  - `components/scaling/AiScalingSettings.tsx` (admin settings);
  - `ScalingQueue.tsx` (staff home);
  - `MyWorkoutScaling.tsx` (Box today and the assigned workout panel);
  - namespace `Scaling` in all 12 locales.
- Tests:
  - `scaling_controller_test.exs`, `scaling_domain_test.exs`, `anthropic_scaling_advisor_test.exs`;
  - `scaling-review.test.ts`;
  - Playwright `e2e/scaling.spec.ts`, which runs at the end of the phase.
