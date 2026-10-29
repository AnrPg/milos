# ADR-301: AI agents as delegated principals, durable runs and safety policy
Date: 2026-10-29
Status: Proposed (v4 plan, `docs/plans/v4-agent-first-novel-features.md` §3.4–3.10, V4-M1)

## Context
ANR (2026-10-29) wants AI agents to be first-class in Palee and the code to support several agents
working together. Agents will read photos written by members (whiteboard scores), answer staff
questions over gym data, and propose changes. They meet untrusted input, private data and state
changes, the combination behind prompt-injection incidents (Meta "Agents Rule of Two", OWASP Top 10
for Agentic Applications 2026). Delegation standards are still drafts on top of OAuth Token Exchange
(RFC 8693), whose `act` claim is informational only.

## Decision
1. **Agents are principals.** `TenantContext` gains an additive `principal` field
   (`kind: :user | :agent`, agent, on-behalf-of user, run, delegation, scopes). Agent kinds:
   `delegated` (acts for one person), `service` (acts for the gym; the triggering person or event
   is recorded), `platform` (vendor, no gym data without explicit grant).
2. **Rights are an intersection computed on every call:** the person's current capabilities (ADR-099)
   ∩ the delegation's scopes ∩ the agent definition's allowed operations. RLS is unchanged, so an
   agent never crosses tenants. Short-lived JWTs (`sub=agent:…`, `act`, `org`, `run_id`, `jti`) are
   checked against the database on each call; the token alone is never trusted.
3. **New context `Palee.Agents`** with `agent_definitions`, `agent_delegations`, `agent_runs`
   (state machine, `parent_run_id`, budget, Rule-of-Two legs), append-only `agent_run_steps`,
   `agent_approvals` and opt-in, visible, expiring `agent_memories`. All tenant-scoped and purged
   with the gym (ADR-117).
4. **Safety policy enforced in code:**
   - Rule of Two per run: a run that has read untrusted input and private data cannot change state
     or communicate externally without a human approval.
   - Untrusted content (`:user_generated`, images) is read only by a quarantined extractor with no
     tools that returns schema-validated data (port `Agents.Ports.QuarantinedExtractor`).
   - Approval ladder by operation risk: reads within rights; reversible writes only if the
     delegation allows, with undo; irreversible, outward and money operations always need approval
     of the exact previewed input (ADR-300).
   - Budgets (steps, tokens, cost, time) per run and per gym per day, rate limits, kill switches per
     agent, per gym and global, and visible labels on everything an agent writes (AI Act art. 50).
5. **Durable runs** execute as Oban jobs with a checkpoint per step; waiting for approval holds no
   process; each operation call uses `Idempotency-Key = run_id:step`.
6. **Models behind one port** `Agents.Ports.LlmProvider` (messages, tools, structured output,
   images, usage) with `Anthropic`, `Gemini`, `Scripted` and `Recorded` adapters, per-task routing and
   fallback in config, versioned prompts under `priv/agents/prompts`, metering through ADR-152 with
   `operation_id = run_id`, and OpenTelemetry GenAI spans.
7. **Multi-agent** only through the registered operation `agents.delegate`: a child run gets a
   delegation equal to or narrower than its parent's, a share of the parent's budget and a maximum
   depth. External agents connect through MCP (ADR-302); the definition fields map to an A2A Agent
   Card so an A2A adapter can be added later without model changes.
8. **Deterministic first.** An agent may run without an LLM (e.g. finding a substitute coach); it
   still gets the same identity, audit and limits.

## Rationale
Server-side intersection on every call removes reliance on unratified token-chaining standards and
closes token-splicing attacks. Encoding the Rule of Two and the risk ladder as policy turns security
guidance into testable invariants. Durable, checkpointed runs survive the container restarts we have
already seen, and a single provider port keeps model choice a configuration decision.

## Alternatives Considered
- **Agents as ordinary users with their own accounts:** easy, but loses on-behalf-of accountability
  and makes revocation and scope narrowing manual.
- **Trusting signed tokens without a database check:** faster, but revocation would wait for
  expiry, and delegation chains could be spliced.
- **A general-purpose agent framework library:** less code now, but ties the domain to a framework's
  abstractions and release cycle; the needed loop is small and must follow ADR-043.

## Consequences
- New policy test matrix (all combinations of legs, risks and scopes), a red-team prompt-injection
  suite and an eval harness (`mix palee.agents.eval`) gate prompt and model changes.
- Approvals surface as notifications and a staff dashboard card, not a new tab (vision §4).
- Existing AI adapters move to `LlmProvider` one at a time, with evals before and after.
