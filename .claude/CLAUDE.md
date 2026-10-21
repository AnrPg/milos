## vexp - Context-Aware AI Coding <!-- vexp v2.0.31 -->

### MANDATORY: use vexp pipeline - do NOT grep or glob the codebase
For every task - bug fixes, features, refactors, debugging:
**call `run_pipeline` FIRST**. It executes context search + impact analysis +
memory recall in a single call, returning compressed results.

Do NOT use grep, glob, Bash, or cat to search/explore the codebase.
vexp returns pre-indexed, graph-ranked context that is more relevant and
uses fewer tokens than manual searching. Prefer `get_skeleton` over Read to
inspect files (detail: minimal/standard/detailed, 70-90% token savings).
Only use Read when you need exact raw content to edit a specific line.

### Primary Tool
- `run_pipeline` - **USE THIS FOR EVERYTHING**. Single call that runs
  capsule + impact + memory server-side. Returns compressed results.
  Auto-detects intent (debug/modify/refactor/explore) from your task.
  Includes full file content for pivots.
  Examples:
  - `run_pipeline({ "task": "fix JWT validation bug" })` - auto-detect
  - `run_pipeline({ "task": "refactor db layer", "preset": "refactor" })` - explicit
  - `run_pipeline({ "task": "add auth", "observation": "using JWT" })` - save insight in same call

### Other MCP tools (use only when run_pipeline is insufficient)
- `get_skeleton` - **preferred over Read** for inspecting files (minimal/standard/detailed detail levels, 70-90% token savings)
- `index_status` - indexing status and health check
- `expand_vexp_ref` - expand V-REF hash placeholders in v2 compact output

### Workflow
1. `run_pipeline("your task")` - ALWAYS FIRST. Returns pivots + impact + memories in 1 call
2. Need more detail on a file? Use `get_skeleton({ files: [...], detail: "detailed" })` - avoid Read unless editing
3. Make targeted changes based on the context returned
4. `run_pipeline` again ONLY if you need more context during implementation
5. Do NOT chain multiple vexp calls - one `run_pipeline` replaces capsule + impact + memory + observation

### Subagent / Explore / Plan mode
- Subagents CAN and MUST call `run_pipeline` - always include the task description
- The PreToolUse hook blocks Grep/Glob when vexp daemon is running
- Do NOT spawn Agent(Explore) to freely search - call `run_pipeline` first,
  then pass the returned context into the agent prompt if needed
- Always: `run_pipeline` -> get context -> spawn agent with context

### Smart Features (automatic - no action needed)
- **Intent Detection**: auto-detects from your task keywords. "fix bug" -> Debug, "refactor" -> blast-radius, "add" -> Modify
- **Hybrid Search**: keyword + semantic + graph centrality ranking
- **Session Memory**: auto-captures observations; memories auto-surfaced in results
- **LSP Bridge**: VS Code captures type-resolved call edges
- **Change Coupling**: co-changed files included as related context

### Advanced Parameters
- `preset: "debug"` - forces debug mode (capsule+tests+impact+memory)
- `preset: "refactor"` - deep impact analysis (depth 5)
- `max_tokens: 12000` - increase total budget for complex tasks
- `include_tests: true` - include test files in results
- `include_file_content: false` - omit full file content (lighter response)

### Multi-Repo Workspaces
`run_pipeline` auto-queries all indexed repos. Use `repos: ["alias"]` to scope.
Use `index_status` to discover available repo aliases.
<!-- /vexp -->
## Product direction
Member-app work must follow `docs/product/2026-10-15-palee-product-vision-and-ia.md` (source of truth; its §4 principles are non-negotiable)
and the final clickable design `docs/product/mockups/palee-ia-mockup.html`.
`docs/product/mockups/palee-bottom-bar-exploration.html` is SUPERSEDED — reasoning only, never implement from it.
To start implementation work, use the kickoff prompt in `docs/product/IMPLEMENTATION_PROMPT.md`.
If the vexp MCP server is not connected in a session, fall back to the built-in search tools rather than stopping.

## Multi-agent workflow
Several agents work on this repo at once (local sessions and cloud sessions). They never share a disk, only GitHub.
- GitHub is the single source of truth. Never rely on files that are not committed and pushed; anything outside the repo (e.g. a local wrapper folder's `.claude/`) is invisible to other agents.
- Integration branch: `main` (the redesign was merged into it on 2026-10-21). Branch off it per task (`feat/<topic>`, `chore/<topic>`) and merge back via PR. Small `.claude/` or docs-only changes may go straight to `main`.
- Before starting work: `git fetch origin` and bring your branch up to date with the integration branch (merge, don't rewrite shared history).
- Commit small, push often. Never end a session with unpushed work.
- Before pushing to a shared branch: `git pull --no-rebase` first; resolve conflicts, never force-push a shared branch.
- Don't edit files that another open PR is changing without coordinating in that PR.
- Project-wide Claude config (settings, hooks, skills, this file) lives in `.claude/` in the repo, so every agent loads the same setup.
