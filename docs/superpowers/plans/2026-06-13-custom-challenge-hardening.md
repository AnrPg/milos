# Custom Challenge Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the `custom` seasonal challenge type with a rich multi-condition rules engine, Hall of Fame opt-in leaderboard (expandable on landing page), ephemeral per-completion point breakdown, and admin rules builder UI.

**Architecture:** New `ChallengeRule` domain module evaluates additive point rules at completion time using extended `completion_facts` already available in `RecordWorkoutCompletion`. Progress capping and leaderboard opt-in are managed via a new `challenge_leaderboard_opt_ins` table. Backward compatibility preserved: challenges with `increment_per_completion` continue working unchanged.

**Tech Stack:** Elixir/Phoenix, Ecto, PostgreSQL, React/TypeScript, React Query, Zustand (not used here — plain state), TailwindCSS.

---

## File Map

**New files:**
- `apps/api/priv/repo/migrations/20260613110000_add_last_increment_event_to_user_challenge_progress.exs`
- `apps/api/priv/repo/migrations/20260613120000_create_challenge_leaderboard_opt_ins.exs`
- `apps/api/lib/milos_training/gamification/domain/challenge_rule.ex`
- `apps/api/lib/milos_training/gamification/domain/challenge_leaderboard.ex`
- `apps/api/lib/milos_training/gamification/challenge_leaderboard_opt_in.ex`
- `apps/api/lib/milos_training/application/opt_in_challenge_leaderboard.ex`
- `apps/api/lib/milos_training/application/opt_out_challenge_leaderboard.ex`
- `apps/api/lib/milos_training/application/get_challenge_leaderboard.ex`
- `apps/api/lib/milos_training_web/controllers/challenge_controller.ex`
- `apps/api/test/milos_training/gamification/domain/challenge_rule_test.exs`
- `apps/web/src/components/workouts/ChallengeCard.tsx`

**Modified files:**
- `apps/api/lib/milos_training/gamification/domain/challenge_criteria.ex`
- `apps/api/lib/milos_training/gamification/domain/challenge_progress.ex`
- `apps/api/lib/milos_training/gamification/user_challenge_progress.ex`
- `apps/api/lib/milos_training/gamification/ports/gamification_store.ex`
- `apps/api/lib/milos_training/gamification/gamification_store.ex`
- `apps/api/lib/milos_training/gamification.ex`
- `apps/api/lib/milos_training/infrastructure/gamification/ecto_gamification_store.ex`
- `apps/api/lib/milos_training/gamification/commands/record_workout_completion.ex`
- `apps/api/lib/milos_training/application/complete_workout.ex`
- `apps/api/lib/milos_training/application/get_landing_page.ex`
- `apps/api/lib/milos_training/application/get_admin_challenge.ex`
- `apps/api/lib/milos_training_web/router.ex`
- `apps/web/src/api/challenges.ts`
- `apps/web/src/api/landing.ts`
- `apps/web/src/components/landing-page.tsx`
- `apps/web/src/components/realtime-sync-bridge.tsx`
- `apps/web/src/components/admin-challenges.tsx`

---

## Task 1: Database Migrations

**Files:**
- Create: `apps/api/priv/repo/migrations/20260613110000_add_last_increment_event_to_user_challenge_progress.exs`
- Create: `apps/api/priv/repo/migrations/20260613120000_create_challenge_leaderboard_opt_ins.exs`

- [ ] **Step 1: Write migration for `last_increment_event`**

```elixir
# apps/api/priv/repo/migrations/20260613110000_add_last_increment_event_to_user_challenge_progress.exs
defmodule MilosTraining.Repo.Migrations.AddLastIncrementEventToUserChallengeProgress do
  use Ecto.Migration

  def change do
    alter table(:user_challenge_progress) do
      add :last_increment_event, :map, default: nil
    end
  end
end
```

- [ ] **Step 2: Write migration for `challenge_leaderboard_opt_ins`**

```elixir
# apps/api/priv/repo/migrations/20260613120000_create_challenge_leaderboard_opt_ins.exs
defmodule MilosTraining.Repo.Migrations.CreateChallengeLeaderboardOptIns do
  use Ecto.Migration

  def change do
    create table(:challenge_leaderboard_opt_ins, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :challenge_id, references(:seasonal_challenges, type: :binary_id, on_delete: :delete_all), null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:challenge_leaderboard_opt_ins, [:user_id, :challenge_id])
    create index(:challenge_leaderboard_opt_ins, [:challenge_id])
  end
end
```

- [ ] **Step 3: Run migrations in Docker**

```bash
docker exec milos-api-1 sh -c "cd /app && mix ecto.migrate"
```

Expected output: two migration success lines.

- [ ] **Step 4: Commit**

```bash
git add apps/api/priv/repo/migrations/20260613110000_add_last_increment_event_to_user_challenge_progress.exs \
        apps/api/priv/repo/migrations/20260613120000_create_challenge_leaderboard_opt_ins.exs
git commit -m "feat(db): add last_increment_event to challenge progress + leaderboard opt-ins table"
```

---

## Task 2: `ChallengeRule` Domain Module

**Files:**
- Create: `apps/api/lib/milos_training/gamification/domain/challenge_rule.ex`
- Create: `apps/api/test/milos_training/gamification/domain/challenge_rule_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# apps/api/test/milos_training/gamification/domain/challenge_rule_test.exs
defmodule MilosTraining.Gamification.Domain.ChallengeRuleTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Gamification.Domain.ChallengeRule

  describe "evaluate/2 — workout_type" do
    test "awards points when workout type matches" do
      rule = %{"condition" => "workout_type", "type" => "crossfit", "points" => 3}
      assert ChallengeRule.evaluate(rule, %{workout_type: "crossfit"}) == 3
    end

    test "returns 0 when workout type does not match" do
      rule = %{"condition" => "workout_type", "type" => "crossfit", "points" => 3}
      assert ChallengeRule.evaluate(rule, %{workout_type: "strength"}) == 0
    end

    test "returns 0 when workout_type is nil" do
      rule = %{"condition" => "workout_type", "type" => "crossfit", "points" => 3}
      assert ChallengeRule.evaluate(rule, %{workout_type: nil}) == 0
    end
  end

  describe "evaluate/2 — scale_level" do
    test "awards points when scale level matches" do
      rule = %{"condition" => "scale_level", "slug" => "rx", "points" => 2}
      assert ChallengeRule.evaluate(rule, %{scale_level_slug: "rx"}) == 2
    end

    test "returns 0 when scale level does not match" do
      rule = %{"condition" => "scale_level", "slug" => "rx", "points" => 2}
      assert ChallengeRule.evaluate(rule, %{scale_level_slug: "scaled"}) == 0
    end

    test "returns 0 when scale_level_slug is nil" do
      rule = %{"condition" => "scale_level", "slug" => "rx", "points" => 2}
      assert ChallengeRule.evaluate(rule, %{scale_level_slug: nil}) == 0
    end
  end

  describe "evaluate/2 — pr_beaten" do
    test "awards points when pr_count > 0" do
      rule = %{"condition" => "pr_beaten", "points" => 5}
      assert ChallengeRule.evaluate(rule, %{pr_count: 2}) == 5
    end

    test "returns 0 when pr_count is 0" do
      rule = %{"condition" => "pr_beaten", "points" => 5}
      assert ChallengeRule.evaluate(rule, %{pr_count: 0}) == 0
    end
  end

  describe "evaluate/2 — weekly_consistency" do
    test "awards points when consistency_score meets threshold" do
      rule = %{"condition" => "weekly_consistency", "threshold" => 50, "points" => 3}
      assert ChallengeRule.evaluate(rule, %{consistency_score: 0.6}) == 3
    end

    test "awards points when consistency_score equals threshold exactly" do
      rule = %{"condition" => "weekly_consistency", "threshold" => 50, "points" => 3}
      assert ChallengeRule.evaluate(rule, %{consistency_score: 0.5}) == 3
    end

    test "returns 0 when below threshold" do
      rule = %{"condition" => "weekly_consistency", "threshold" => 50, "points" => 3}
      assert ChallengeRule.evaluate(rule, %{consistency_score: 0.3}) == 0
    end
  end

  describe "evaluate/2 — rare_workout_type" do
    test "awards points when type is rarely done (below threshold)" do
      rule = %{"condition" => "rare_workout_type", "threshold_pct" => 10, "points" => 4}
      # 0 out of 9 previous = 0% ratio
      assert ChallengeRule.evaluate(rule, %{prev_type_count: 0, total_prev_completions: 9}) == 4
    end

    test "awards points on first-ever workout (0 previous completions)" do
      rule = %{"condition" => "rare_workout_type", "threshold_pct" => 10, "points" => 4}
      assert ChallengeRule.evaluate(rule, %{prev_type_count: 0, total_prev_completions: 0}) == 4
    end

    test "returns 0 when type is done more than threshold percent of the time" do
      rule = %{"condition" => "rare_workout_type", "threshold_pct" => 10, "points" => 4}
      # 5 out of 9 = 55%
      assert ChallengeRule.evaluate(rule, %{prev_type_count: 5, total_prev_completions: 9}) == 0
    end

    test "uses default threshold_pct of 10 when absent" do
      rule = %{"condition" => "rare_workout_type", "points" => 4}
      assert ChallengeRule.evaluate(rule, %{prev_type_count: 0, total_prev_completions: 9}) == 4
    end
  end

  describe "evaluate/2 — team_workout_streak" do
    test "awards points when team workout count meets min_count" do
      rule = %{"condition" => "team_workout_streak", "min_count" => 2, "points" => 3}
      assert ChallengeRule.evaluate(rule, %{team_workout_count: 3}) == 3
    end

    test "awards points when exactly at min_count" do
      rule = %{"condition" => "team_workout_streak", "min_count" => 2, "points" => 3}
      assert ChallengeRule.evaluate(rule, %{team_workout_count: 2}) == 3
    end

    test "returns 0 when below min_count" do
      rule = %{"condition" => "team_workout_streak", "min_count" => 2, "points" => 3}
      assert ChallengeRule.evaluate(rule, %{team_workout_count: 1}) == 0
    end
  end

  describe "label/1" do
    test "returns the rule's label when present" do
      rule = %{"condition" => "pr_beaten", "points" => 5, "label" => "for crushing a PR"}
      assert ChallengeRule.label(rule) == "for crushing a PR"
    end

    test "returns default label when label is absent" do
      rule = %{"condition" => "pr_beaten", "points" => 5}
      assert ChallengeRule.label(rule) == "for beating a PR"
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd apps/api && MIX_ENV=test mix test test/milos_training/gamification/domain/challenge_rule_test.exs 2>&1 | head -20
```

Expected: compile error — module not found.

- [ ] **Step 3: Implement `ChallengeRule`**

```elixir
# apps/api/lib/milos_training/gamification/domain/challenge_rule.ex
defmodule MilosTraining.Gamification.Domain.ChallengeRule do
  @doc "Returns `points` if the rule's condition is met, 0 otherwise."
  def evaluate(%{"condition" => "workout_type", "type" => type, "points" => points}, facts) do
    if to_string(Map.get(facts, :workout_type)) == to_string(type), do: points, else: 0
  end

  def evaluate(%{"condition" => "scale_level", "slug" => slug, "points" => points}, facts) do
    if to_string(Map.get(facts, :scale_level_slug)) == to_string(slug), do: points, else: 0
  end

  def evaluate(%{"condition" => "pr_beaten", "points" => points}, facts) do
    if Map.get(facts, :pr_count, 0) > 0, do: points, else: 0
  end

  def evaluate(%{"condition" => "weekly_consistency", "threshold" => threshold, "points" => points}, facts) do
    score = Map.get(facts, :consistency_score, 0.0)
    if score * 100 >= threshold, do: points, else: 0
  end

  def evaluate(%{"condition" => "rare_workout_type", "points" => points} = rule, facts) do
    threshold_pct = Map.get(rule, "threshold_pct", 10)
    prev = Map.get(facts, :prev_type_count, 0)
    total = Map.get(facts, :total_prev_completions, 0)
    ratio = if total == 0, do: 0.0, else: prev / total * 100
    if ratio < threshold_pct, do: points, else: 0
  end

  def evaluate(%{"condition" => "team_workout_streak", "min_count" => min_count, "points" => points}, facts) do
    count = Map.get(facts, :team_workout_count, 0)
    if count >= min_count, do: points, else: 0
  end

  def evaluate(_rule, _facts), do: 0

  @doc "Returns the display label for this rule's earned points."
  def label(%{"label" => lbl}) when is_binary(lbl) and lbl != "", do: lbl
  def label(rule), do: default_label(rule)

  defp default_label(%{"condition" => "workout_type", "type" => type}), do: "for a #{type} workout"
  defp default_label(%{"condition" => "scale_level", "slug" => slug}), do: "for #{slug} performance"
  defp default_label(%{"condition" => "pr_beaten"}), do: "for beating a PR"
  defp default_label(%{"condition" => "weekly_consistency"}), do: "for weekly consistency"
  defp default_label(%{"condition" => "rare_workout_type"}), do: "for exploring a new workout type"
  defp default_label(%{"condition" => "team_workout_streak"}), do: "for team participation"
  defp default_label(_), do: "for this workout"
end
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
cd apps/api && MIX_ENV=test mix test test/milos_training/gamification/domain/challenge_rule_test.exs
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add apps/api/lib/milos_training/gamification/domain/challenge_rule.ex \
        apps/api/test/milos_training/gamification/domain/challenge_rule_test.exs
git commit -m "feat(domain): add ChallengeRule — multi-condition points evaluator"
```

---

## Task 3: `ChallengeCriteria` — Rules Format Support

**Files:**
- Modify: `apps/api/lib/milos_training/gamification/domain/challenge_criteria.ex`

- [ ] **Step 1: Replace `normalize_value("custom", ...)` and add helpers**

Replace the existing `normalize_value("custom", ...)` clause and add `has_rules?/1` and `rules/1`:

```elixir
# Full replacement of apps/api/lib/milos_training/gamification/domain/challenge_criteria.ex
defmodule MilosTraining.Gamification.Domain.ChallengeCriteria do
  @valid_types ~w(workout_count workout_type_count pr_count custom)
  @training_types ~w(crossfit strength gymnastics aerobics flexibility recovery)
  @rule_conditions ~w(workout_type scale_level pr_beaten weekly_consistency rare_workout_type team_workout_streak)

  def normalize(criteria_type, criteria_value) do
    type = normalize_type(criteria_type)
    value = criteria_value || %{}

    with :ok <- validate_type(type),
         {:ok, normalized_count} <- fetch_positive_integer(value, "count"),
         {:ok, normalized_value} <- normalize_value(type, normalized_count, value) do
      {:ok, %{criteria_type: type, criteria_value: normalized_value}}
    end
  end

  def target(%{criteria_value: criteria_value}) do
    case fetch_positive_integer(criteria_value || %{}, "count") do
      {:ok, count} -> count
      :error -> 1
    end
  end

  def has_rules?(criteria_value) when is_map(criteria_value) do
    rules = Map.get(criteria_value, "rules") || Map.get(criteria_value, :rules)
    is_list(rules) and rules != []
  end
  def has_rules?(_), do: false

  def rules(criteria_value) when is_map(criteria_value) do
    Map.get(criteria_value, "rules") || Map.get(criteria_value, :rules) || []
  end
  def rules(_), do: []

  def increment_per_completion(%{criteria_value: criteria_value}) do
    case fetch_positive_integer(criteria_value || %{}, "increment_per_completion") do
      {:ok, increment} -> increment
      :error -> 1
    end
  end

  def increment_label(%{criteria_value: criteria_value}) do
    Map.get(criteria_value || %{}, "increment_label") ||
      Map.get(criteria_value || %{}, :increment_label)
  end

  defp validate_type(type) when type in @valid_types, do: :ok
  defp validate_type(_type), do: {:error, [criteria_type: "is invalid"]}

  defp normalize_value("workout_count", count, _value), do: {:ok, %{"count" => count}}
  defp normalize_value("pr_count", count, _value), do: {:ok, %{"count" => count}}

  defp normalize_value("workout_type_count", count, value) do
    type_filter = Map.get(value, "type_filter") || Map.get(value, :type_filter)

    if type_filter in @training_types do
      {:ok, %{"count" => count, "type_filter" => type_filter}}
    else
      {:error, [criteria_value: "type_filter must be a valid training type"]}
    end
  end

  defp normalize_value("custom", count, value) do
    rules = Map.get(value, "rules") || Map.get(value, :rules)

    cond do
      is_list(rules) and rules != [] ->
        case validate_rules(rules) do
          :ok -> {:ok, %{"count" => count, "rules" => normalize_rules(rules)}}
          {:error, reason} -> {:error, reason}
        end

      true ->
        case fetch_positive_integer(value, "increment_per_completion") do
          {:ok, increment} ->
            label = Map.get(value, "increment_label") || Map.get(value, :increment_label)
            normalized = %{"count" => count, "increment_per_completion" => increment}
            normalized = if is_binary(label) and String.length(label) <= 160, do: Map.put(normalized, "increment_label", label), else: normalized
            {:ok, normalized}

          :error ->
            {:error, [criteria_value: "must have increment_per_completion or rules"]}
        end
    end
  end

  defp validate_rules(rules) do
    Enum.reduce_while(rules, :ok, fn rule, :ok ->
      case validate_rule(rule) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_rule(%{"condition" => condition} = rule) when condition in @rule_conditions do
    case fetch_positive_integer(rule, "points") do
      {:ok, _} -> :ok
      :error -> {:error, [criteria_value: "each rule must have points >= 1"]}
    end
  end
  defp validate_rule(_), do: {:error, [criteria_value: "rule condition must be one of: #{Enum.join(@rule_conditions, ", ")}"]}

  defp normalize_rules(rules) do
    Enum.map(rules, fn rule ->
      base = %{
        "condition" => rule["condition"] || to_string(rule[:condition]),
        "points" => cast_integer(rule["points"] || rule[:points])
      }

      rule
      |> Map.take(~w(type slug threshold threshold_pct min_count label))
      |> Map.merge(base)
    end)
  end

  defp normalize_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_type(type) when is_binary(type), do: type
  defp normalize_type(_type), do: nil

  defp fetch_positive_integer(map, key) do
    value = Map.get(map, key) || Map.get(map, String.to_atom(key))

    case cast_integer(value) do
      int when is_integer(int) and int > 0 -> {:ok, int}
      _other -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp cast_integer(value) when is_integer(value), do: value
  defp cast_integer(value) when is_float(value) and trunc(value) == value, do: trunc(value)

  defp cast_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> :error
    end
  end

  defp cast_integer(_value), do: :error
end
```

- [ ] **Step 2: Compile check**

```bash
cd apps/api && MIX_ENV=test mix compile 2>&1 | grep -E "error|warning" | head -20
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add apps/api/lib/milos_training/gamification/domain/challenge_criteria.ex
git commit -m "feat(domain): ChallengeCriteria — add rules format + has_rules?/rules/increment_label helpers"
```

---

## Task 4: `ChallengeProgress` — Rules Engine

**Files:**
- Modify: `apps/api/lib/milos_training/gamification/domain/challenge_progress.ex`

- [ ] **Step 1: Replace module entirely**

```elixir
# apps/api/lib/milos_training/gamification/domain/challenge_progress.ex
defmodule MilosTraining.Gamification.Domain.ChallengeProgress do
  alias MilosTraining.Gamification.Domain.{ChallengeCriteria, ChallengeRule}

  @doc "Advances progress and returns a result map with increment, events, new progress, target, completed?."
  def advance(challenge, progress, completion_facts) do
    {increment, events} = evaluate(challenge, completion_facts)
    target = target(challenge)
    next_progress = progress + increment

    %{
      increment: increment,
      events: events,
      progress: next_progress,
      target: target,
      completed?: target > 0 and next_progress >= target
    }
  end

  def target(challenge), do: ChallengeCriteria.target(challenge)

  defp evaluate(%{criteria_type: type, criteria_value: cv}, facts)
       when type in ["custom", :custom] do
    if ChallengeCriteria.has_rules?(cv) do
      rules = ChallengeCriteria.rules(cv)
      resolved = resolve_team_count(facts, nil)

      events =
        Enum.flat_map(rules, fn rule ->
          case ChallengeRule.evaluate(rule, resolved) do
            0 -> []
            pts -> [%{points: pts, label: ChallengeRule.label(rule)}]
          end
        end)

      total = Enum.reduce(events, 0, fn %{points: p}, acc -> acc + p end)
      {total, events}
    else
      pts = ChallengeCriteria.increment_per_completion(%{criteria_value: cv})
      lbl = ChallengeCriteria.increment_label(%{criteria_value: cv}) || "for this workout"
      events = if pts > 0, do: [%{points: pts, label: lbl}], else: []
      {pts, events}
    end
  end

  defp evaluate(%{criteria_type: type}, _facts) when type in ["workout_count", :workout_count],
    do: {1, []}

  defp evaluate(%{criteria_type: type, criteria_value: cv}, %{workout_type: wt})
       when type in ["workout_type_count", :workout_type_count] do
    filter = Map.get(cv || %{}, "type_filter") || Map.get(cv || %{}, :type_filter)
    if to_string(filter) == to_string(wt), do: {1, []}, else: {0, []}
  end

  defp evaluate(%{criteria_type: type}, %{pr_count: pr_count})
       when type in ["pr_count", :pr_count],
       do: {pr_count, []}

  defp evaluate(_challenge, _facts), do: {0, []}

  # If completion_facts carries a team_workout_count_fn closure, resolve it now.
  # For rules engine the challenge is already in scope so fn/1 is called with nil
  # (the closure captures challenge internally via `list_active_challenges`).
  # In practice, the closure in RecordWorkoutCompletion captures challenge as argument.
  defp resolve_team_count(%{team_workout_count_fn: fun} = facts, challenge) when is_function(fun, 1) do
    Map.put(facts, :team_workout_count, fun.(challenge))
  end
  defp resolve_team_count(facts, _challenge), do: facts
end
```

Note: `resolve_team_count` with `nil` challenge works because the closure in `RecordWorkoutCompletion` is `fn challenge -> team_workout_count_for_challenge(challenge, ...) end` — the `challenge` arg is passed from the `evaluate` call site. We need to pass the actual challenge to `evaluate`. Fix the `evaluate` private function to take the challenge:

```elixir
# Replace the evaluate clauses above — pass challenge explicitly so team_workout_count_fn gets it:
defp evaluate(%{criteria_type: type, criteria_value: cv} = challenge, facts)
     when type in ["custom", :custom] do
  if ChallengeCriteria.has_rules?(cv) do
    rules = ChallengeCriteria.rules(cv)
    resolved = resolve_team_count(facts, challenge)
    # ... rest unchanged
```

And `resolve_team_count`:
```elixir
defp resolve_team_count(%{team_workout_count_fn: fun} = facts, challenge) when is_function(fun, 1) do
  Map.put(facts, :team_workout_count, fun.(challenge))
end
defp resolve_team_count(facts, _challenge), do: facts
```

Full corrected file:

```elixir
defmodule MilosTraining.Gamification.Domain.ChallengeProgress do
  alias MilosTraining.Gamification.Domain.{ChallengeCriteria, ChallengeRule}

  def advance(challenge, progress, completion_facts) do
    {increment, events} = evaluate(challenge, completion_facts)
    target = target(challenge)
    next_progress = progress + increment

    %{
      increment: increment,
      events: events,
      progress: next_progress,
      target: target,
      completed?: target > 0 and next_progress >= target
    }
  end

  def target(challenge), do: ChallengeCriteria.target(challenge)

  defp evaluate(%{criteria_type: type, criteria_value: cv} = challenge, facts)
       when type in ["custom", :custom] do
    if ChallengeCriteria.has_rules?(cv) do
      rules = ChallengeCriteria.rules(cv)
      resolved = resolve_team_count(facts, challenge)

      events =
        Enum.flat_map(rules, fn rule ->
          case ChallengeRule.evaluate(rule, resolved) do
            0 -> []
            pts -> [%{points: pts, label: ChallengeRule.label(rule)}]
          end
        end)

      total = Enum.reduce(events, 0, fn %{points: p}, acc -> acc + p end)
      {total, events}
    else
      pts = ChallengeCriteria.increment_per_completion(%{criteria_value: cv})
      lbl = ChallengeCriteria.increment_label(%{criteria_value: cv}) || "for this workout"
      events = if pts > 0, do: [%{points: pts, label: lbl}], else: []
      {pts, events}
    end
  end

  defp evaluate(%{criteria_type: type}, _facts)
       when type in ["workout_count", :workout_count],
       do: {1, []}

  defp evaluate(%{criteria_type: type, criteria_value: cv}, %{workout_type: wt})
       when type in ["workout_type_count", :workout_type_count] do
    filter = Map.get(cv || %{}, "type_filter") || Map.get(cv || %{}, :type_filter)
    if to_string(filter) == to_string(wt), do: {1, []}, else: {0, []}
  end

  defp evaluate(%{criteria_type: type}, %{pr_count: pr_count})
       when type in ["pr_count", :pr_count],
       do: {pr_count, []}

  defp evaluate(_challenge, _facts), do: {0, []}

  defp resolve_team_count(%{team_workout_count_fn: fun} = facts, challenge) when is_function(fun, 1) do
    Map.put(facts, :team_workout_count, fun.(challenge))
  end
  defp resolve_team_count(facts, _challenge), do: facts
end
```

- [ ] **Step 2: Compile check**

```bash
cd apps/api && MIX_ENV=test mix compile 2>&1 | grep -E "^error" | head -10
```

- [ ] **Step 3: Commit**

```bash
git add apps/api/lib/milos_training/gamification/domain/challenge_progress.ex
git commit -m "feat(domain): ChallengeProgress — rules engine, events list, team_workout_count_fn resolver"
```

---

## Task 5: `ChallengeLeaderboard` Domain + `ChallengeLeaderboardOptIn` Schema

**Files:**
- Create: `apps/api/lib/milos_training/gamification/domain/challenge_leaderboard.ex`
- Create: `apps/api/lib/milos_training/gamification/challenge_leaderboard_opt_in.ex`

- [ ] **Step 1: Create `ChallengeLeaderboard` domain module**

```elixir
# apps/api/lib/milos_training/gamification/domain/challenge_leaderboard.ex
defmodule MilosTraining.Gamification.Domain.ChallengeLeaderboard do
  @doc "Adds :rank to each participant. Ties share the same rank."
  def rank([]), do: []

  def rank(participants) do
    sorted = Enum.sort_by(participants, & &1.progress, :desc)

    {ranked, _} =
      Enum.map_reduce(sorted, {1, nil}, fn participant, {next_rank, prev_progress} ->
        rank = if participant.progress == prev_progress, do: next_rank - 1, else: next_rank
        {Map.put(participant, :rank, rank), {next_rank + 1, participant.progress}}
      end)

    ranked
  end
end
```

- [ ] **Step 2: Create `ChallengeLeaderboardOptIn` Ecto schema**

```elixir
# apps/api/lib/milos_training/gamification/challenge_leaderboard_opt_in.ex
defmodule MilosTraining.Gamification.ChallengeLeaderboardOptIn do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "challenge_leaderboard_opt_ins" do
    field :user_id, :binary_id
    field :challenge_id, :binary_id
    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(opt_in \\ %__MODULE__{}, params) do
    opt_in
    |> cast(params, [:user_id, :challenge_id])
    |> validate_required([:user_id, :challenge_id])
    |> unique_constraint([:user_id, :challenge_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:challenge_id)
  end
end
```

- [ ] **Step 3: Update `UserChallengeProgress` schema** to add `last_increment_event`

In `apps/api/lib/milos_training/gamification/user_challenge_progress.ex`, add the field and cast:

```elixir
schema "user_challenge_progress" do
  field :user_id, :binary_id
  field :challenge_id, :binary_id
  field :progress, :integer, default: 0
  field :completed_at, :utc_datetime_usec
  field :last_increment_event, :map, default: nil   # NEW

  timestamps(type: :utc_datetime_usec)
end

def changeset(progress \\ %__MODULE__{}, params) do
  progress
  |> cast(params, [:user_id, :challenge_id, :progress, :completed_at, :last_increment_event])  # added last_increment_event
  |> validate_required([:user_id, :challenge_id, :progress])
  |> validate_number(:progress, greater_than_or_equal_to: 0)
  |> unique_constraint([:user_id, :challenge_id])
  |> foreign_key_constraint(:user_id)
  |> foreign_key_constraint(:challenge_id)
end
```

- [ ] **Step 4: Compile check**

```bash
cd apps/api && MIX_ENV=test mix compile 2>&1 | grep "^error" | head -10
```

- [ ] **Step 5: Commit**

```bash
git add apps/api/lib/milos_training/gamification/domain/challenge_leaderboard.ex \
        apps/api/lib/milos_training/gamification/challenge_leaderboard_opt_in.ex \
        apps/api/lib/milos_training/gamification/user_challenge_progress.ex
git commit -m "feat(domain): ChallengeLeaderboard rank helper + opt-in schema + last_increment_event on progress"
```

---

## Task 6: `GamificationStore` Port + `EctoGamificationStore` + `Gamification` Context

**Files:**
- Modify: `apps/api/lib/milos_training/gamification/ports/gamification_store.ex`
- Modify: `apps/api/lib/milos_training/gamification/gamification_store.ex`
- Modify: `apps/api/lib/milos_training/gamification.ex`
- Modify: `apps/api/lib/milos_training/infrastructure/gamification/ecto_gamification_store.ex`

- [ ] **Step 1: Add new callbacks to port**

Append to `apps/api/lib/milos_training/gamification/ports/gamification_store.ex`:

```elixir
  @callback opt_in_challenge_leaderboard(user_id :: Ecto.UUID.t(), challenge_id :: Ecto.UUID.t()) ::
              {:ok, any()} | {:error, any()}
  @callback opt_out_challenge_leaderboard(user_id :: Ecto.UUID.t(), challenge_id :: Ecto.UUID.t()) :: :ok
  @callback challenge_leaderboard_opted_in?(user_id :: Ecto.UUID.t(), challenge_id :: Ecto.UUID.t()) :: boolean()
  @callback list_challenge_leaderboard_participants(challenge_id :: Ecto.UUID.t()) :: [map()]
```

- [ ] **Step 2: Add delegations to `GamificationStore` boundary module**

In `apps/api/lib/milos_training/gamification/gamification_store.ex`, the module delegates to the adapter. Add:

```elixir
defdelegate opt_in_challenge_leaderboard(user_id, challenge_id), to: store()
defdelegate opt_out_challenge_leaderboard(user_id, challenge_id), to: store()
defdelegate challenge_leaderboard_opted_in?(user_id, challenge_id), to: store()
defdelegate list_challenge_leaderboard_participants(challenge_id), to: store()
```

(Find the existing `defdelegate` calls and add these alongside them.)

- [ ] **Step 3: Add delegations to `Gamification` context facade**

In `apps/api/lib/milos_training/gamification.ex`, find existing `defdelegate` calls and add:

```elixir
defdelegate opt_in_challenge_leaderboard(user_id, challenge_id), to: GamificationStore
defdelegate opt_out_challenge_leaderboard(user_id, challenge_id), to: GamificationStore
defdelegate challenge_leaderboard_opted_in?(user_id, challenge_id), to: GamificationStore
defdelegate list_challenge_leaderboard_participants(challenge_id), to: GamificationStore
```

- [ ] **Step 4: Implement new callbacks in `EctoGamificationStore`**

Add the following to `apps/api/lib/milos_training/infrastructure/gamification/ecto_gamification_store.ex`:

First, add `ChallengeLeaderboardOptIn` to the existing alias block at the top:
```elixir
alias MilosTraining.Gamification.{
  ChallengeLeaderboardOptIn,   # ADD
  GamificationSetting,
  LeaderboardOptIn,
  SeasonalChallenge,
  UserAchievement,
  UserChallengeProgress,
  UserStat
}
```

Then add the four new `@impl true` functions:

```elixir
@impl true
def opt_in_challenge_leaderboard(user_id, challenge_id) do
  case Repo.get_by(ChallengeLeaderboardOptIn, user_id: user_id, challenge_id: challenge_id) do
    nil ->
      %ChallengeLeaderboardOptIn{}
      |> ChallengeLeaderboardOptIn.changeset(%{user_id: user_id, challenge_id: challenge_id})
      |> Repo.insert()
      |> case do
        {:ok, record} -> {:ok, record}
        {:error, changeset} -> {:error, changeset}
      end

    existing ->
      {:ok, existing}
  end
end

@impl true
def opt_out_challenge_leaderboard(user_id, challenge_id) do
  ChallengeLeaderboardOptIn
  |> where([o], o.user_id == ^user_id and o.challenge_id == ^challenge_id)
  |> Repo.delete_all()

  :ok
end

@impl true
def challenge_leaderboard_opted_in?(user_id, challenge_id) do
  ChallengeLeaderboardOptIn
  |> where([o], o.user_id == ^user_id and o.challenge_id == ^challenge_id)
  |> Repo.exists?()
end

@impl true
def list_challenge_leaderboard_participants(challenge_id) do
  UserChallengeProgress
  |> join(:inner, [p], o in ChallengeLeaderboardOptIn,
      on: p.user_id == o.user_id and p.challenge_id == o.challenge_id)
  |> where([p, _o], p.challenge_id == ^challenge_id)
  |> order_by([p, _o], desc: p.progress)
  |> limit(50)
  |> Repo.all()
  |> Enum.map(&normalize_progress/1)
end
```

- [ ] **Step 5: Update `normalize_progress/1` to include `last_increment_event`**

Find `defp normalize_progress(%UserChallengeProgress{} = progress)` in `EctoGamificationStore` and add the new field:

```elixir
defp normalize_progress(%UserChallengeProgress{} = progress) do
  %{
    id: progress.id,
    user_id: progress.user_id,
    challenge_id: progress.challenge_id,
    progress: progress.progress,
    completed_at: progress.completed_at,
    last_increment_event: progress.last_increment_event,   # NEW
    inserted_at: progress.inserted_at,
    updated_at: progress.updated_at
  }
end
```

- [ ] **Step 6: Compile check**

```bash
cd apps/api && MIX_ENV=test mix compile 2>&1 | grep "^error" | head -10
```

- [ ] **Step 7: Commit**

```bash
git add apps/api/lib/milos_training/gamification/ports/gamification_store.ex \
        apps/api/lib/milos_training/gamification/gamification_store.ex \
        apps/api/lib/milos_training/gamification.ex \
        apps/api/lib/milos_training/infrastructure/gamification/ecto_gamification_store.ex
git commit -m "feat(infra): challenge leaderboard opt-in store operations + last_increment_event in progress"
```

---

## Task 7: `RecordWorkoutCompletion` — Extended Facts + Increments

**Files:**
- Modify: `apps/api/lib/milos_training/gamification/commands/record_workout_completion.ex`

- [ ] **Step 1: Replace `call/1` body and `persist_challenge_progress`**

Full replacement of `apps/api/lib/milos_training/gamification/commands/record_workout_completion.ex`:

```elixir
defmodule MilosTraining.Gamification.Commands.RecordWorkoutCompletion do
  alias MilosTraining.Gamification.Domain.{
    AchievementRules,
    ChallengeProgress,
    PRDetector,
    StreakCalculator
  }

  alias MilosTraining.Gamification.GamificationStore

  def call(%{
        execution:
          %{id: execution_id, user_id: user_id, completed_at_utc: completed_at} = execution,
        completed_executions: completed_executions,
        workout_lookup: workout_lookup,
        account: account,
        settings: settings
      }) do
    current_execution = Enum.find(completed_executions, &(&1.id == execution_id)) || execution
    previous_scores = previous_scores(completed_executions, execution_id, workout_lookup)

    current_scores =
      enrich_scores(
        current_execution.section_scores || [],
        workout_lookup[current_execution.master_workout_id]
      )

    pr_scores = PRDetector.detect(current_scores, previous_scores)
    existing_stats = GamificationStore.get_user_stats(user_id) || %{longest_streak: 0}
    completed_dates = Enum.map(completed_executions, &DateTime.to_date(&1.completed_at_utc))

    streaks =
      StreakCalculator.update(existing_stats,
        completed_dates: completed_dates,
        current_date: Date.utc_today(),
        anchor_date: signup_anchor_date(account, completed_dates),
        target: settings.weekly_workout_target,
        shield_reset_day: settings.streak_shield_reset_day
      )

    type_counts = workout_type_counts(completed_executions, workout_lookup)
    current_type = get_workout_type(current_execution, workout_lookup)
    total_prev = max(0, length(completed_executions) - 1)
    prev_type_count = max(0, Map.get(type_counts, current_type, 0) - 1)

    completion_facts = %{
      workout_type: current_type,
      pr_count: length(pr_scores),
      scale_level_slug: current_execution.scale_level_slug,
      consistency_score: streaks.consistency_score,
      prev_type_count: prev_type_count,
      total_prev_completions: total_prev,
      team_workout_count_fn: fn challenge ->
        team_workout_count_for_challenge(challenge, completed_executions, workout_lookup)
      end
    }

    GamificationStore.transaction(fn ->
      with {:ok, _pr_events} <- persist_pr_events(user_id, execution_id, pr_scores, completed_at),
           total_prs <- GamificationStore.count_achievements_by_prefix(user_id, "pr_event:"),
           stats <- build_stats(user_id, streaks, completed_executions, total_prs, execution),
           {:ok, _stats} <- GamificationStore.upsert_user_stats(stats),
           {:ok, _badges} <-
             persist_achievements(
               AchievementRules.milestone_badges(stats, type_counts),
               user_id,
               completed_at
             ),
           {:ok, challenge_result} <-
             persist_challenge_progress(user_id, current_execution, completion_facts, completed_at) do
        {:ok,
         %{
           challenge_completions: challenge_result.completions,
           challenge_increments: challenge_result.increments
         }}
      end
    end)
  end

  defp build_stats(user_id, streaks, completed_executions, total_prs, current_execution) do
    %{
      user_id: user_id,
      current_streak: streaks.current_streak,
      longest_streak: streaks.longest_streak,
      total_workouts: length(completed_executions),
      total_prs: total_prs,
      current_streak_shields: streaks.current_streak_shields,
      last_workout_at: List.last(completed_executions, current_execution).completed_at_utc,
      consistency_score: streaks.consistency_score,
      updated_at: DateTime.utc_now()
    }
  end

  defp persist_pr_events(user_id, execution_id, pr_scores, completed_at) do
    pr_scores
    |> Enum.map(&"pr_event:#{execution_id}:#{&1.section_id}")
    |> persist_achievements(user_id, completed_at)
  end

  defp persist_achievements(badge_keys, user_id, completed_at) do
    Enum.reduce_while(badge_keys, {:ok, []}, fn badge_key, {:ok, acc} ->
      case GamificationStore.create_achievement(%{
             user_id: user_id,
             badge_key: badge_key,
             earned_at: completed_at
           }) do
        {:ok, achievement} -> {:cont, {:ok, [achievement | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, achievements} -> {:ok, Enum.reverse(achievements)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_challenge_progress(user_id, _execution, completion_facts, completed_at) do
    completion_date = DateTime.to_date(completed_at)

    GamificationStore.list_active_challenges(completion_date)
    |> Enum.reduce_while({:ok, %{completions: [], increments: []}}, fn challenge, {:ok, acc} ->
      current_progress =
        GamificationStore.get_user_challenge_progress(user_id, challenge.id) ||
          %{progress: 0, completed_at: nil, last_increment_event: nil}

      update =
        ChallengeProgress.advance(challenge, current_progress.progress || 0, completion_facts)

      opted_in = GamificationStore.challenge_leaderboard_opted_in?(user_id, challenge.id)
      next_progress = if opted_in, do: update.progress, else: min(update.progress, update.target)

      next_completed_at =
        if is_nil(current_progress.completed_at) and update.completed?,
          do: completed_at,
          else: current_progress.completed_at

      last_increment_event =
        if update.increment > 0 do
          %{
            "total_points" => update.increment,
            "events" => Enum.map(update.events, &%{"points" => &1.points, "label" => &1.label})
          }
        else
          current_progress[:last_increment_event]
        end

      case GamificationStore.upsert_user_challenge_progress(%{
             user_id: user_id,
             challenge_id: challenge.id,
             progress: next_progress,
             completed_at: next_completed_at,
             last_increment_event: last_increment_event
           }) do
        {:ok, _progress} ->
          new_increment =
            if update.increment > 0,
              do: [
                %{
                  challenge_id: challenge.id,
                  title: challenge.title,
                  total_points: update.increment,
                  events: update.events
                }
              ],
              else: []

          maybe_complete_challenge(
            user_id,
            challenge,
            current_progress,
            update.completed?,
            completed_at,
            acc,
            new_increment
          )

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp maybe_complete_challenge(
         user_id,
         challenge,
         current_progress,
         true,
         completed_at,
         acc,
         new_increment
       )
       when is_nil(current_progress.completed_at) do
    case GamificationStore.create_achievement(%{
           user_id: user_id,
           badge_key: challenge.badge_key,
           earned_at: completed_at
         }) do
      {:ok, _achievement} ->
        completion = %{
          user_id: user_id,
          challenge_id: challenge.id,
          title: challenge.title,
          badge_label: challenge.badge_label,
          badge_key: challenge.badge_key
        }

        {:cont,
         {:ok,
          %{
            completions: acc.completions ++ [completion],
            increments: acc.increments ++ new_increment
          }}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp maybe_complete_challenge(_user_id, _challenge, _current_progress, _completed?, _completed_at, acc, new_increment) do
    {:cont, {:ok, %{completions: acc.completions, increments: acc.increments ++ new_increment}}}
  end

  defp get_workout_type(execution, workout_lookup) do
    case workout_lookup[execution.master_workout_id] do
      %{type: type} when is_binary(type) -> type
      _ -> nil
    end
  end

  defp team_workout_count_for_challenge(challenge, completed_executions, workout_lookup) do
    completed_executions
    |> Enum.filter(fn e ->
      date = DateTime.to_date(e.completed_at_utc)
      Date.compare(date, challenge.starts_at) in [:gt, :eq] and
        Date.compare(date, challenge.ends_at) in [:lt, :eq]
    end)
    |> Enum.count(fn e ->
      case workout_lookup[e.master_workout_id] do
        %{is_team_workout: true} -> true
        _ -> false
      end
    end)
  end

  defp previous_scores(executions, current_execution_id, workout_lookup) do
    executions
    |> Enum.reject(&(&1.id == current_execution_id))
    |> Enum.flat_map(fn execution ->
      enrich_scores(execution.section_scores || [], workout_lookup[execution.master_workout_id])
    end)
  end

  defp enrich_scores(section_scores, nil), do: Enum.map(section_scores, &normalize_score(&1, %{}))

  defp enrich_scores(section_scores, workout) do
    score_configs =
      workout.sections
      |> flatten_sections()
      |> Map.new(fn section -> {section.id, section[:score_config] || %{}} end)

    Enum.map(section_scores, &normalize_score(&1, score_configs))
  end

  defp normalize_score(score, score_configs) do
    section_id = score[:section_id] || score["section_id"]
    config = Map.get(score_configs, section_id, %{})

    %{
      section_id: section_id,
      value: score[:value] || score["value"],
      unit: score[:unit] || score["unit"] || config[:unit] || config["unit"],
      score_type: config[:type] || config["type"] || :reps
    }
  end

  defp flatten_sections(sections) do
    Enum.flat_map(sections, fn section ->
      [section | flatten_sections(Map.get(section, :sections, []))]
    end)
  end

  defp workout_type_counts(executions, workout_lookup) do
    executions
    |> Enum.reduce(%{}, fn execution, acc ->
      case workout_lookup[execution.master_workout_id] do
        %{type: type} when is_binary(type) -> Map.update(acc, type, 1, &(&1 + 1))
        _ -> acc
      end
    end)
  end

  defp signup_anchor_date(%{inserted_at: %DateTime{} = inserted_at}, _completed_dates),
    do: DateTime.to_date(inserted_at)

  defp signup_anchor_date(%{inserted_at: %NaiveDateTime{} = inserted_at}, _completed_dates),
    do: NaiveDateTime.to_date(inserted_at)

  defp signup_anchor_date(_, completed_dates), do: Enum.min(completed_dates)
end
```

- [ ] **Step 2: Compile check**

```bash
cd apps/api && MIX_ENV=test mix compile 2>&1 | grep "^error" | head -10
```

- [ ] **Step 3: Run existing gamification tests**

```bash
cd apps/api && MIX_ENV=test mix test test/milos_training/gamification/ --timeout 30000
```

Expected: existing tests still pass (the public `call/1` interface is unchanged from callers' perspective).

- [ ] **Step 4: Commit**

```bash
git add apps/api/lib/milos_training/gamification/commands/record_workout_completion.ex
git commit -m "feat(app): RecordWorkoutCompletion — extended completion_facts, challenge_increments, rules engine wiring"
```

---

## Task 8: `GetLandingPage` — Bug Fix + Enrichment

**Files:**
- Modify: `apps/api/lib/milos_training/application/get_landing_page.ex`

- [ ] **Step 1: Replace the active_challenges mapping block**

Find the block starting at `active_challenges =` in `get_landing_page.ex`. Replace the entire `Enum.map` block:

```elixir
active_challenges =
  Date.utc_today()
  |> Gamification.get_active_challenges()
  |> Enum.map(fn challenge ->
    progress =
      Gamification.challenge_progress(user.id, challenge.id) ||
        %{progress: 0, completed_at: nil, last_increment_event: nil}

    target = ChallengeProgress.target(challenge)
    current_progress = progress.progress || 0
    is_opted_in = Gamification.challenge_leaderboard_opted_in?(user.id, challenge.id)

    completions_remaining =
      cond do
        target <= 0 -> 0
        current_progress >= target -> 0
        ChallengeCriteria.has_rules?(challenge.criteria_value) ->
          rules = ChallengeCriteria.rules(challenge.criteria_value)
          max_per_completion = Enum.reduce(rules, 0, fn r, acc -> acc + (r["points"] || 0) end)
          if max_per_completion > 0,
            do: max(0, ceil((target - current_progress) / max_per_completion)),
            else: 0
        true ->
          inc = ChallengeCriteria.increment_per_completion(challenge)
          max(0, ceil((target - current_progress) / inc))
      end

    %{
      id: challenge.id,
      title: challenge.title,
      description: challenge.description,
      badge_key: challenge.badge_key,
      badge_label: challenge.badge_label,
      criteria_type: challenge.criteria_type,
      target: target,
      progress: current_progress,
      completed_at: progress.completed_at,
      completed: not is_nil(progress.completed_at),
      starts_at: challenge.starts_at,
      ends_at: challenge.ends_at,
      has_rules: ChallengeCriteria.has_rules?(challenge.criteria_value),
      increment_per_completion: unless(ChallengeCriteria.has_rules?(challenge.criteria_value),
        do: ChallengeCriteria.increment_per_completion(challenge),
        else: nil
      ),
      completions_remaining: completions_remaining,
      is_opted_in: is_opted_in,
      last_progress_event: progress[:last_increment_event]
    }
  end)
```

Add the needed aliases at the top of `GetLandingPage`:
```elixir
alias MilosTraining.Gamification.Domain.{ChallengeCriteria, ChallengeProgress}
```

- [ ] **Step 2: Compile check**

```bash
cd apps/api && MIX_ENV=test mix compile 2>&1 | grep "^error" | head -10
```

- [ ] **Step 3: Commit**

```bash
git add apps/api/lib/milos_training/application/get_landing_page.ex
git commit -m "fix(app): GetLandingPage — use ChallengeProgress.target, expose increment semantics + is_opted_in + completions_remaining"
```

---

## Task 9: Hall of Fame Application Services + `CompleteWorkout` Broadcast + `GetAdminChallenge`

**Files:**
- Create: `apps/api/lib/milos_training/application/opt_in_challenge_leaderboard.ex`
- Create: `apps/api/lib/milos_training/application/opt_out_challenge_leaderboard.ex`
- Create: `apps/api/lib/milos_training/application/get_challenge_leaderboard.ex`
- Modify: `apps/api/lib/milos_training/application/complete_workout.ex`
- Modify: `apps/api/lib/milos_training/application/get_admin_challenge.ex`

- [ ] **Step 1: `OptInChallengeLeaderboard`**

```elixir
# apps/api/lib/milos_training/application/opt_in_challenge_leaderboard.ex
defmodule MilosTraining.Application.OptInChallengeLeaderboard do
  alias MilosTraining.Gamification

  def call(user_id, challenge_id) do
    case Gamification.get_challenge(challenge_id) do
      nil -> {:error, :not_found}
      _challenge -> Gamification.opt_in_challenge_leaderboard(user_id, challenge_id)
    end
  end
end
```

- [ ] **Step 2: `OptOutChallengeLeaderboard`**

```elixir
# apps/api/lib/milos_training/application/opt_out_challenge_leaderboard.ex
defmodule MilosTraining.Application.OptOutChallengeLeaderboard do
  alias MilosTraining.Gamification

  def call(user_id, challenge_id) do
    Gamification.opt_out_challenge_leaderboard(user_id, challenge_id)
    :ok
  end
end
```

- [ ] **Step 3: `GetChallengeLeaderboard`**

```elixir
# apps/api/lib/milos_training/application/get_challenge_leaderboard.ex
defmodule MilosTraining.Application.GetChallengeLeaderboard do
  alias MilosTraining.{Gamification, Identity}
  alias MilosTraining.Gamification.Domain.{ChallengeLeaderboard, ChallengeProgress}

  def call(challenge_id, requesting_user_id) do
    with challenge when not is_nil(challenge) <- Gamification.get_challenge(challenge_id) do
      target = ChallengeProgress.target(challenge)
      opted_in_progress = Gamification.list_challenge_leaderboard_participants(challenge_id)

      user_lookup =
        opted_in_progress
        |> Enum.map(& &1.user_id)
        |> then(&Identity.list_users_by_ids/1)
        |> Map.new(&{&1.id, &1})

      participants =
        opted_in_progress
        |> Enum.map(fn row ->
          user = Map.get(user_lookup, row.user_id, %{})

          %{
            user_id: row.user_id,
            nickname: Map.get(user, :nickname),
            progress: row.progress,
            target: target,
            completed_at: row.completed_at
          }
        end)
        |> ChallengeLeaderboard.rank()

      my_entry = Enum.find(participants, &(&1.user_id == requesting_user_id))

      {:ok,
       %{
         challenge_id: challenge_id,
         participants: Enum.take(participants, 50),
         my_rank: my_entry && my_entry.rank,
         my_progress: my_entry && my_entry.progress
       }}
    else
      nil -> {:error, :not_found}
    end
  end
end
```

Note: `Identity.list_users_by_ids/1` may not exist yet. Check and add it:

```bash
grep -n "list_users_by_ids\|list_all_users\|list_by_ids" /home/rodochrousbisbiki/MyApps/milos/apps/api/lib/milos_training/identity.ex | head -10
```

If `list_users_by_ids/1` doesn't exist, add to `Identity`:
```elixir
# In Identity context (identity.ex or identity/queries/):
def list_users_by_ids([]), do: []
def list_users_by_ids(ids) do
  Repo.all(from u in User, where: u.id in ^ids)
  |> Enum.map(&normalize_user/1)
end
```

Find the existing user normalization pattern and use it.

- [ ] **Step 4: Update `CompleteWorkout` to broadcast `challenge_increments`**

In `apps/api/lib/milos_training/application/complete_workout.ex`, update `process_completion/1`:

```elixir
def process_completion(%{user_id: user_id} = execution) do
  account = Identity.find_by_id(user_id)
  settings = Gamification.get_settings()

  completed_executions =
    user_id
    |> Execution.list_executions_for_user()
    |> Enum.filter(& &1.completed_at_utc)
    |> Enum.sort_by(&DateTime.to_unix(&1.completed_at_utc, :microsecond))

  workout_lookup = build_workout_lookup(completed_executions)
  admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

  case Gamification.record_workout_completion(%{
         execution: execution,
         account: account,
         settings: settings,
         completed_executions: completed_executions,
         workout_lookup: workout_lookup
       }) do
    {:ok, result} ->
      _ = refresh_leaderboard()
      InvalidateLandingPages.for_users([user_id | admin_ids])

      BroadcastUserSync.for_user(
        user_id,
        ["landing"],
        reason: "challenge_progress_advanced",
        payload: %{increments: result.challenge_increments}
      )

      BroadcastUserSync.for_users(
        admin_ids,
        ["admin_challenges"],
        reason: "challenge_progress_updated",
        payload: %{user_id: user_id, execution_id: execution.id}
      )

      _ = dispatch_challenge_notifications(result.challenge_completions)
      :ok

    error ->
      InvalidateLandingPages.for_users([user_id | admin_ids])
      error
  end
end
```

- [ ] **Step 5: Update `GetAdminChallenge` participant rows**

In `apps/api/lib/milos_training/application/get_admin_challenge.ex`, update `normalize_participant/3`:

```elixir
defp normalize_participant(user, progress_rows, challenge) do
  progress_row = Map.get(progress_rows, user.id, %{})
  target = ChallengeProgress.target(challenge)
  progress = Map.get(progress_row, :progress, 0)
  completed_at = Map.get(progress_row, :completed_at)
  updated_at = Map.get(progress_row, :updated_at)

  # Completions tracking for custom challenges
  {completions_done, completions_remaining} =
    if challenge.criteria_type in ["custom", :custom] do
      inc = effective_increment(challenge)
      done = if inc > 0, do: div(progress, inc), else: 0
      remaining = if inc > 0, do: max(0, ceil((target - progress) / inc)), else: 0
      {done, remaining}
    else
      {nil, nil}
    end

  %{
    user_id: user.id,
    nickname: user.nickname,
    role: to_string(user.role),
    progress: progress,
    target: target,
    completion_ratio: completion_ratio(progress, target),
    completed_at: completed_at,
    updated_at: updated_at,
    completions_done: completions_done,
    completions_remaining: completions_remaining
  }
end

defp effective_increment(challenge) do
  alias MilosTraining.Gamification.Domain.ChallengeCriteria

  if ChallengeCriteria.has_rules?(challenge.criteria_value) do
    rules = ChallengeCriteria.rules(challenge.criteria_value)
    Enum.reduce(rules, 0, fn r, acc -> acc + (r["points"] || 0) end)
  else
    ChallengeCriteria.increment_per_completion(challenge)
  end
end
```

Add the alias at the top: `alias MilosTraining.Gamification.Domain.{ChallengeProgress}` (already present) and `ChallengeCriteria`.

- [ ] **Step 6: Compile check**

```bash
cd apps/api && MIX_ENV=test mix compile 2>&1 | grep "^error" | head -10
```

- [ ] **Step 7: Commit**

```bash
git add apps/api/lib/milos_training/application/opt_in_challenge_leaderboard.ex \
        apps/api/lib/milos_training/application/opt_out_challenge_leaderboard.ex \
        apps/api/lib/milos_training/application/get_challenge_leaderboard.ex \
        apps/api/lib/milos_training/application/complete_workout.ex \
        apps/api/lib/milos_training/application/get_admin_challenge.ex
git commit -m "feat(app): Hall of Fame services, CompleteWorkout broadcast, GetAdminChallenge completions_done/remaining"
```

---

## Task 10: API Layer — `ChallengeController` + Router

**Files:**
- Create: `apps/api/lib/milos_training_web/controllers/challenge_controller.ex`
- Modify: `apps/api/lib/milos_training_web/router.ex`

- [ ] **Step 1: Create `ChallengeController`**

```elixir
# apps/api/lib/milos_training_web/controllers/challenge_controller.ex
defmodule MilosTrainingWeb.ChallengeController do
  use MilosTrainingWeb, :controller

  alias Guardian.Plug, as: GuardianPlug

  alias MilosTraining.Application.{
    GetChallengeLeaderboard,
    OptInChallengeLeaderboard,
    OptOutChallengeLeaderboard
  }

  action_fallback MilosTrainingWeb.FallbackController

  def leaderboard(conn, %{"id" => id}) do
    current_user = GuardianPlug.current_resource(conn)

    with {:ok, payload} <- GetChallengeLeaderboard.call(id, current_user.id) do
      json(conn, payload)
    end
  end

  def opt_in(conn, %{"id" => id}) do
    current_user = GuardianPlug.current_resource(conn)

    with {:ok, _} <- OptInChallengeLeaderboard.call(current_user.id, id) do
      json(conn, %{opted_in: true})
    end
  end

  def opt_out(conn, %{"id" => id}) do
    current_user = GuardianPlug.current_resource(conn)
    :ok = OptOutChallengeLeaderboard.call(current_user.id, id)
    json(conn, %{opted_in: false})
  end
end
```

- [ ] **Step 2: Add routes to router**

In `apps/api/lib/milos_training_web/router.ex`, find the `scope "/api"` block with `pipe_through([:api, :authenticated, :user_only])` and add three new routes:

```elixir
    get("/challenges/:id/leaderboard", ChallengeController, :leaderboard)
    post("/challenges/:id/opt_in", ChallengeController, :opt_in)
    delete("/challenges/:id/opt_in", ChallengeController, :opt_out)
```

- [ ] **Step 3: Compile check**

```bash
cd apps/api && MIX_ENV=test mix compile 2>&1 | grep "^error" | head -10
```

- [ ] **Step 4: Run controller tests**

```bash
cd apps/api && MIX_ENV=test mix test test/milos_training_web/controllers/admin_challenge_controller_test.exs
```

Expected: existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/api/lib/milos_training_web/controllers/challenge_controller.ex \
        apps/api/lib/milos_training_web/router.ex
git commit -m "feat(api): ChallengeController — leaderboard, opt_in, opt_out endpoints"
```

---

## Task 11: Frontend — API Types + Functions

**Files:**
- Modify: `apps/web/src/api/challenges.ts`
- Modify: `apps/web/src/api/landing.ts`

- [ ] **Step 1: Update `challenges.ts`**

```typescript
// apps/web/src/api/challenges.ts
import { apiRequest } from "@/api/client";

export type ChallengeRule = {
  condition:
    | "workout_type"
    | "scale_level"
    | "pr_beaten"
    | "weekly_consistency"
    | "rare_workout_type"
    | "team_workout_streak";
  type?: string;
  slug?: string;
  threshold?: number;
  threshold_pct?: number;
  min_count?: number;
  points: number;
  label?: string;
};

export type AdminChallengeRecord = {
  id: string;
  title: string;
  description: string | null;
  criteria_type: string;
  criteria_value: Record<string, unknown>;
  badge_key: string;
  badge_label: string;
  starts_at: string;
  ends_at: string;
  progress_summary: {
    participants: number;
    completed: number;
    average_progress: number;
    completion_rate: number;
    target: number;
  };
};

export type ChallengeParticipantRecord = {
  user_id: string;
  nickname: string | null;
  role: string | null;
  progress: number;
  target: number;
  completion_ratio: number;
  completed_at: string | null;
  updated_at: string;
  completions_done: number | null;
  completions_remaining: number | null;
};

export type SaveChallengePayload = {
  title: string;
  description?: string | null;
  criteria_type: "workout_count" | "workout_type_count" | "pr_count" | "custom";
  criteria_value: Record<string, unknown>;
  badge_key: string;
  badge_label: string;
  starts_at: string;
  ends_at: string;
};

export type AdminChallengeDetailResponse = {
  challenge: AdminChallengeRecord;
  participants: ChallengeParticipantRecord[];
};

export type ChallengeLeaderboardEntry = {
  user_id: string;
  nickname: string | null;
  progress: number;
  target: number;
  completed_at: string | null;
  rank: number;
};

export type ChallengeLeaderboardResponse = {
  challenge_id: string;
  participants: ChallengeLeaderboardEntry[];
  my_rank: number | null;
  my_progress: number | null;
};

export async function fetchAdminChallenges(token: string) {
  return apiRequest<{ challenges: AdminChallengeRecord[] }>("/admin/challenges", { token });
}

export async function fetchAdminChallenge(token: string, id: string) {
  return apiRequest<AdminChallengeDetailResponse>(`/admin/challenges/${id}`, { token });
}

export async function createAdminChallenge(token: string, payload: SaveChallengePayload) {
  return apiRequest<{ challenge: AdminChallengeRecord }>("/admin/challenges", {
    method: "POST",
    token,
    body: payload,
  });
}

export async function updateAdminChallenge(token: string, id: string, payload: SaveChallengePayload) {
  return apiRequest<{ challenge: AdminChallengeRecord }>(`/admin/challenges/${id}`, {
    method: "PATCH",
    token,
    body: payload,
  });
}

export async function fetchChallengeLeaderboard(token: string, id: string) {
  return apiRequest<ChallengeLeaderboardResponse>(`/challenges/${id}/leaderboard`, { token });
}

export async function optInChallenge(token: string, id: string) {
  return apiRequest<{ opted_in: boolean }>(`/challenges/${id}/opt_in`, {
    method: "POST",
    token,
  });
}

export async function optOutChallenge(token: string, id: string) {
  return apiRequest<{ opted_in: boolean }>(`/challenges/${id}/opt_in`, {
    method: "DELETE",
    token,
  });
}
```

- [ ] **Step 2: Update `ChallengeRecord` in `landing.ts`**

Replace the existing `ChallengeRecord` type:

```typescript
export type LastProgressEvent = {
  total_points: number;
  events: Array<{ points: number; label: string }>;
};

export type ChallengeRecord = {
  id: string;
  title: string;
  description: string | null;
  badge_key: string;
  badge_label: string;
  criteria_type: string;
  target: number;
  progress: number;
  completed: boolean;
  completed_at: string | null;
  starts_at: string;
  ends_at: string;
  has_rules: boolean;
  increment_per_completion: number | null;
  completions_remaining: number;
  is_opted_in: boolean;
  last_progress_event: LastProgressEvent | null;
};
```

- [ ] **Step 3: TypeScript compile check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | head -30
```

Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/api/challenges.ts apps/web/src/api/landing.ts
git commit -m "feat(web-api): update ChallengeRecord + ChallengeParticipant types, add leaderboard/opt-in API functions"
```

---

## Task 12: Frontend — Admin Rules Builder

**Files:**
- Modify: `apps/web/src/components/admin-challenges.tsx`

- [ ] **Step 1: Add `RuleFormRow` type and update `ChallengeFormState`**

At the top of the file, after existing imports, add:

```typescript
type RuleCondition =
  | "workout_type"
  | "scale_level"
  | "pr_beaten"
  | "weekly_consistency"
  | "rare_workout_type"
  | "team_workout_streak";

type RuleFormRow = {
  id: string;
  condition: RuleCondition;
  type: string;        // workout_type
  slug: string;        // scale_level
  threshold: string;   // weekly_consistency
  threshold_pct: string; // rare_workout_type
  min_count: string;   // team_workout_streak
  points: string;
  label: string;
};

const CONDITION_LABELS: Record<RuleCondition, string> = {
  workout_type: "Workout type",
  scale_level: "Scale level",
  pr_beaten: "PR beaten",
  weekly_consistency: "Weekly consistency",
  rare_workout_type: "Rare workout type",
  team_workout_streak: "Team workout streak",
};

function defaultRuleRow(): RuleFormRow {
  return {
    id: Math.random().toString(36).slice(2),
    condition: "pr_beaten",
    type: "crossfit",
    slug: "rx",
    threshold: "50",
    threshold_pct: "10",
    min_count: "2",
    points: "1",
    label: "",
  };
}
```

Update `ChallengeFormState` to add `rules` and `incrementLabel`, and update `emptyForm`:

```typescript
type ChallengeFormState = {
  title: string;
  description: string;
  criteriaType: CriteriaType;
  targetCount: string;
  typeFilter: string;
  incrementPerCompletion: string;
  incrementLabel: string;    // NEW
  rules: RuleFormRow[];      // NEW
  badgeLabel: string;
  startsAt: string;
  endsAt: string;
};

function emptyForm(): ChallengeFormState {
  return {
    title: "",
    description: "",
    criteriaType: "workout_count",
    targetCount: "2",
    typeFilter: "crossfit",
    incrementPerCompletion: "1",
    incrementLabel: "",
    rules: [],
    badgeLabel: "",
    startsAt: formatLocalDate(new Date()),
    endsAt: formatLocalDate(addLocalDays(new Date(), 7)),
  };
}
```

- [ ] **Step 2: Update `payloadFromForm` and `hydrateForm`**

```typescript
function payloadFromForm(form: ChallengeFormState): SaveChallengePayload {
  const count = Number(form.targetCount || 0);

  let criteria_value: Record<string, unknown>;
  if (form.criteriaType === "workout_type_count") {
    criteria_value = { count, type_filter: form.typeFilter };
  } else if (form.criteriaType === "custom") {
    if (form.rules.length > 0) {
      criteria_value = {
        count,
        rules: form.rules.map((r) => {
          const base: Record<string, unknown> = {
            condition: r.condition,
            points: Number(r.points || 1),
          };
          if (r.label.trim()) base.label = r.label.trim();
          if (r.condition === "workout_type") base.type = r.type;
          if (r.condition === "scale_level") base.slug = r.slug;
          if (r.condition === "weekly_consistency") base.threshold = Number(r.threshold);
          if (r.condition === "rare_workout_type") base.threshold_pct = Number(r.threshold_pct);
          if (r.condition === "team_workout_streak") base.min_count = Number(r.min_count);
          return base;
        }),
      };
    } else {
      criteria_value = {
        count,
        increment_per_completion: Number(form.incrementPerCompletion || 1),
        ...(form.incrementLabel.trim() ? { increment_label: form.incrementLabel.trim() } : {}),
      };
    }
  } else {
    criteria_value = { count };
  }

  return {
    title: form.title.trim(),
    description: form.description.trim() || null,
    criteria_type: form.criteriaType,
    criteria_value,
    badge_key: `challenge_${slugify(form.badgeLabel || form.title)}`,
    badge_label: (form.badgeLabel || form.title).trim(),
    starts_at: form.startsAt,
    ends_at: form.endsAt,
  };
}

function hydrateForm(challenge: AdminChallengeRecord): ChallengeFormState {
  const cv = challenge.criteria_value;
  const rawRules = cv.rules as Array<Record<string, unknown>> | undefined;

  const rules: RuleFormRow[] = (rawRules ?? []).map((r) => ({
    id: Math.random().toString(36).slice(2),
    condition: (r.condition as RuleCondition) || "pr_beaten",
    type: String(r.type ?? "crossfit"),
    slug: String(r.slug ?? "rx"),
    threshold: String(r.threshold ?? "50"),
    threshold_pct: String(r.threshold_pct ?? "10"),
    min_count: String(r.min_count ?? "2"),
    points: String(r.points ?? "1"),
    label: String(r.label ?? ""),
  }));

  return {
    title: challenge.title,
    description: challenge.description ?? "",
    criteriaType: challenge.criteria_type as CriteriaType,
    targetCount: String(cv.count ?? 0),
    typeFilter: String(cv.type_filter ?? "crossfit"),
    incrementPerCompletion: String(cv.increment_per_completion ?? 1),
    incrementLabel: String(cv.increment_label ?? ""),
    rules,
    badgeLabel: challenge.badge_label,
    startsAt: challenge.starts_at,
    endsAt: challenge.ends_at,
  };
}
```

- [ ] **Step 3: Update `criteriaSummary`**

```typescript
function criteriaSummary(challenge: Pick<AdminChallengeRecord, "criteria_type" | "criteria_value">) {
  const cv = challenge.criteria_value;
  const count = typeof cv.count === "number" ? cv.count : Number(cv.count ?? 0);

  switch (challenge.criteria_type) {
    case "workout_type_count":
      return `${count} ${String(cv.type_filter ?? "targeted")} workouts`;
    case "pr_count":
      return `${count} PRs`;
    case "custom": {
      const rules = cv.rules as Array<Record<string, unknown>> | undefined;
      if (rules && rules.length > 0) {
        const maxPts = rules.reduce((sum, r) => sum + Number(r.points ?? 0), 0);
        return `Reach ${count} pts · up to ${maxPts} pts per workout`;
      }
      const inc = Number(cv.increment_per_completion ?? 1);
      return `Reach ${count} pts (+${inc} per completion)`;
    }
    default:
      return `${count} workouts`;
  }
}
```

- [ ] **Step 4: Add `RuleRowEditor` component and update the form JSX**

Add this component above `AdminChallenges`:

```typescript
function RuleRowEditor({
  row,
  onChange,
  onRemove,
}: {
  row: RuleFormRow;
  onChange: (updated: RuleFormRow) => void;
  onRemove: () => void;
}) {
  const inputStyle = {
    background: "#0d0d18",
    borderColor: "#1a1a28",
    color: "#F0EDF8",
  };

  return (
    <div
      className="rounded-[1.2rem] p-3 space-y-2"
      style={{ background: "#0a0a14", border: "1px solid #1a1a28" }}
    >
      <div className="flex flex-wrap items-center gap-2">
        <select
          className="rounded-xl border px-3 py-2 text-xs flex-1"
          style={inputStyle}
          value={row.condition}
          onChange={(e) => onChange({ ...row, condition: e.target.value as RuleCondition })}
        >
          {(Object.keys(CONDITION_LABELS) as RuleCondition[]).map((c) => (
            <option key={c} value={c}>{CONDITION_LABELS[c]}</option>
          ))}
        </select>

        {row.condition === "workout_type" && (
          <select
            className="rounded-xl border px-3 py-2 text-xs"
            style={inputStyle}
            value={row.type}
            onChange={(e) => onChange({ ...row, type: e.target.value })}
          >
            {TRAINING_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        )}

        {row.condition === "scale_level" && (
          <input
            className="rounded-xl border px-3 py-2 text-xs w-24"
            style={inputStyle}
            placeholder="slug"
            value={row.slug}
            onChange={(e) => onChange({ ...row, slug: e.target.value })}
          />
        )}

        {row.condition === "weekly_consistency" && (
          <label className="flex items-center gap-1 text-xs" style={{ color: "#8888aa" }}>
            ≥
            <input
              className="rounded-xl border px-2 py-2 text-xs w-16"
              style={inputStyle}
              type="number"
              min={1}
              max={100}
              value={row.threshold}
              onChange={(e) => onChange({ ...row, threshold: e.target.value })}
            />
            %
          </label>
        )}

        {row.condition === "rare_workout_type" && (
          <label className="flex items-center gap-1 text-xs" style={{ color: "#8888aa" }}>
            &lt;
            <input
              className="rounded-xl border px-2 py-2 text-xs w-16"
              style={inputStyle}
              type="number"
              min={1}
              max={100}
              value={row.threshold_pct}
              onChange={(e) => onChange({ ...row, threshold_pct: e.target.value })}
            />
            %
          </label>
        )}

        {row.condition === "team_workout_streak" && (
          <label className="flex items-center gap-1 text-xs" style={{ color: "#8888aa" }}>
            ≥
            <input
              className="rounded-xl border px-2 py-2 text-xs w-16"
              style={inputStyle}
              type="number"
              min={1}
              value={row.min_count}
              onChange={(e) => onChange({ ...row, min_count: e.target.value })}
            />
            workouts
          </label>
        )}

        <label className="flex items-center gap-1 text-xs ml-auto" style={{ color: "#8888aa" }}>
          pts:
          <input
            className="rounded-xl border px-2 py-2 text-xs w-16"
            style={inputStyle}
            type="number"
            min={1}
            step={1}
            value={row.points}
            onChange={(e) => onChange({ ...row, points: e.target.value })}
          />
        </label>

        <button
          type="button"
          className="rounded-xl px-2 py-1 text-xs"
          style={{ background: "rgba(217,93,57,0.12)", color: "#e07a5f" }}
          onClick={onRemove}
        >
          ×
        </button>
      </div>

      <input
        className="w-full rounded-xl border px-3 py-2 text-xs"
        style={{ ...inputStyle, color: "#8888aa" }}
        placeholder="Label (e.g. for beating a PR)"
        value={row.label}
        onChange={(e) => onChange({ ...row, label: e.target.value })}
      />
    </div>
  );
}
```

- [ ] **Step 5: Replace the custom criteria section in form JSX**

Find the existing `{form.criteriaType === "custom" ? (` block in the form and replace it with:

```tsx
{form.criteriaType === "custom" ? (
  <div className="space-y-3">
    <div className="flex items-center justify-between">
      <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
        Points Rules
      </span>
      <button
        type="button"
        className="rounded-full px-3 py-1 text-xs font-semibold"
        style={{ background: "#1a1a28", color: "#c0c0d8" }}
        onClick={() => updateForm("rules", [...form.rules, defaultRuleRow()])}
      >
        + Add rule
      </button>
    </div>

    {form.rules.length === 0 ? (
      <>
        <label className="block space-y-2">
          <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
            Increment per completion
          </span>
          <input
            className="w-full rounded-2xl border px-4 py-3 text-sm"
            style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
            value={form.incrementPerCompletion}
            onChange={(e) => updateForm("incrementPerCompletion", e.target.value)}
            type="number"
            min={1}
            step={1}
          />
        </label>
        <label className="block space-y-2">
          <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
            Points label (optional)
          </span>
          <input
            className="w-full rounded-2xl border px-4 py-3 text-sm"
            style={{ background: "#0d0d18", borderColor: "#1a1a28", color: "#F0EDF8" }}
            placeholder="e.g. for completing any workout"
            value={form.incrementLabel}
            onChange={(e) => updateForm("incrementLabel", e.target.value)}
          />
        </label>
      </>
    ) : (
      <div className="space-y-2">
        {form.rules.map((rule, idx) => (
          <RuleRowEditor
            key={rule.id}
            row={rule}
            onChange={(updated) =>
              updateForm(
                "rules",
                form.rules.map((r, i) => (i === idx ? updated : r)),
              )
            }
            onRemove={() =>
              updateForm(
                "rules",
                form.rules.filter((_, i) => i !== idx),
              )
            }
          />
        ))}
      </div>
    )}
  </div>
) : null}
```

- [ ] **Step 6: Update participant table columns for custom challenges**

Find the `<table>` in the participant section and add the two new columns. Replace the `<thead>` and `<tbody>` for participant rows:

```tsx
<thead style={{ background: "#0d0d18", color: "#8888aa" }}>
  <tr>
    <th className="px-4 py-3 text-left font-semibold">User</th>
    <th className="px-4 py-3 text-left font-semibold">Role</th>
    <th className="px-4 py-3 text-left font-semibold">Progress</th>
    <th className="px-4 py-3 text-left font-semibold">Target</th>
    {selectedChallenge?.criteria_type === "custom" ? (
      <>
        <th className="px-4 py-3 text-left font-semibold">Done</th>
        <th className="px-4 py-3 text-left font-semibold">Remaining</th>
      </>
    ) : null}
    <th className="px-4 py-3 text-left font-semibold">Completion</th>
    <th className="px-4 py-3 text-left font-semibold">Completed at</th>
  </tr>
</thead>
```

And in the participant row `<tr>`:
```tsx
{selectedChallenge?.criteria_type === "custom" ? (
  <>
    <td className="px-4 py-3">{participant.completions_done ?? "—"}</td>
    <td className="px-4 py-3">{participant.completions_remaining ?? "—"}</td>
  </>
) : null}
```

(Add after the `Target` cell.)

- [ ] **Step 7: TypeScript compile check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | head -20
```

- [ ] **Step 8: Commit**

```bash
git add apps/web/src/components/admin-challenges.tsx
git commit -m "feat(web): admin rules builder — RuleRowEditor, multi-condition custom challenge form, participant completions columns"
```

---

## Task 13: Frontend — `ChallengeCard` Component + Landing Page + Sync Bridge

**Files:**
- Create: `apps/web/src/components/workouts/ChallengeCard.tsx`
- Modify: `apps/web/src/components/landing-page.tsx`
- Modify: `apps/web/src/components/realtime-sync-bridge.tsx`

- [ ] **Step 1: Create `ChallengeCard.tsx`**

```tsx
// apps/web/src/components/workouts/ChallengeCard.tsx
"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchChallengeLeaderboard, optInChallenge, optOutChallenge } from "@/api/challenges";
import { useSession } from "@/components/session-provider";
import type { ChallengeRecord, LastProgressEvent } from "@/api/landing";

function progressEventText(event: LastProgressEvent): string {
  if (event.events.length === 1) {
    return `You gained +${event.total_points} pts ${event.events[0].label}`;
  }
  const breakdown = event.events.map((e) => `${e.label} (+${e.points})`).join(", ");
  return `+${event.total_points} pts this workout: ${breakdown}`;
}

function completionsRemainingText(challenge: ChallengeRecord): string {
  if (challenge.completed) return "Target reached!";
  const rem = challenge.completions_remaining;
  if (rem === 0) return "Almost there!";
  return `${rem} completion${rem === 1 ? "" : "s"} to go`;
}

export function ChallengeCard({ challenge }: { challenge: ChallengeRecord }) {
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [expanded, setExpanded] = useState(false);

  const leaderboardQuery = useQuery({
    queryKey: ["challenges", challenge.id, "leaderboard"],
    enabled: expanded && Boolean(tokens?.access_token) && challenge.is_opted_in,
    queryFn: () => {
      if (!tokens?.access_token) throw new Error("Not authenticated");
      return fetchChallengeLeaderboard(tokens.access_token, challenge.id);
    },
  });

  const optInMutation = useMutation({
    mutationFn: async () => {
      if (!tokens?.access_token) throw new Error("Not authenticated");
      return optInChallenge(tokens.access_token, challenge.id);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["landing"] });
      void queryClient.invalidateQueries({ queryKey: ["challenges", challenge.id, "leaderboard"] });
    },
  });

  const optOutMutation = useMutation({
    mutationFn: async () => {
      if (!tokens?.access_token) throw new Error("Not authenticated");
      return optOutChallenge(tokens.access_token, challenge.id);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["landing"] });
    },
  });

  const progressPct = Math.min(100, Math.round((challenge.progress / Math.max(challenge.target, 1)) * 100));
  const pastTarget = challenge.progress > challenge.target;
  const isCustom = challenge.criteria_type === "custom";

  return (
    <article className="rounded-[1.6rem] p-4" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
      {/* Header row */}
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>
            {challenge.title}
          </p>
          {challenge.description ? (
            <p className="mt-1 text-xs" style={{ color: "#55556a" }}>
              {challenge.description}
            </p>
          ) : null}
        </div>
        <div className="flex shrink-0 items-center gap-2">
          {challenge.completed ? (
            <span
              className="rounded-full px-2 py-1 text-[10px] font-semibold uppercase tracking-wider"
              style={{ background: "rgba(34,197,94,0.12)", color: "#4ade80", border: "1px solid rgba(34,197,94,0.3)" }}
            >
              {pastTarget && challenge.is_opted_in ? "🏆 In Hall of Fame" : "Target reached!"}
            </span>
          ) : null}
          <span
            className="rounded-full px-2 py-1 text-[10px] font-semibold"
            style={{ background: "rgba(217,93,57,0.12)", color: "#d95d39" }}
          >
            {challenge.badge_label}
          </span>
        </div>
      </div>

      {/* Progress bar */}
      <div className="mt-3 h-2 overflow-hidden rounded-full" style={{ background: "#1a1a28" }}>
        <div
          className="h-full rounded-full transition-all"
          style={{
            width: `${progressPct}%`,
            background: challenge.completed ? "#4ade80" : "#d95d39",
          }}
        />
      </div>

      {/* Progress numbers + completions remaining */}
      <div className="mt-2 flex items-center justify-between text-xs" style={{ color: "#8888aa" }}>
        <span>
          {challenge.progress}/{challenge.target} {isCustom ? "pts" : ""}
          {pastTarget && challenge.is_opted_in ? ` · ${challenge.progress - challenge.target} pts bonus` : ""}
        </span>
        <span style={{ color: challenge.completed ? "#4ade80" : "#8888aa" }}>
          {completionsRemainingText(challenge)}
        </span>
      </div>

      {/* Ephemeral last progress event */}
      {isCustom && challenge.last_progress_event ? (
        <p className="mt-2 text-xs font-medium" style={{ color: "#fbbf24" }}>
          {progressEventText(challenge.last_progress_event)}
        </p>
      ) : null}

      {/* Hall of Fame section — custom challenges only */}
      {isCustom ? (
        <div className="mt-3">
          <div className="flex items-center justify-between gap-2">
            <button
              type="button"
              className="rounded-full px-3 py-1 text-[11px] font-semibold transition-colors"
              style={
                challenge.is_opted_in
                  ? { background: "rgba(251,191,36,0.12)", color: "#fbbf24", border: "1px solid rgba(251,191,36,0.3)" }
                  : { background: "#1a1a28", color: "#8888aa" }
              }
              disabled={optInMutation.isPending || optOutMutation.isPending}
              onClick={() => {
                if (challenge.is_opted_in) {
                  void optOutMutation.mutateAsync();
                } else {
                  void optInMutation.mutateAsync();
                }
              }}
            >
              {challenge.is_opted_in ? "Leave Hall of Fame" : "Join Hall of Fame"}
            </button>

            {challenge.is_opted_in ? (
              <button
                type="button"
                className="text-[11px]"
                style={{ color: "#55556a" }}
                onClick={() => setExpanded((v) => !v)}
              >
                {expanded ? "▲ Hide" : "▼ Hall of Fame"}
              </button>
            ) : null}
          </div>

          {expanded && challenge.is_opted_in ? (
            <div className="mt-3">
              <p className="mb-2 text-[11px] font-semibold uppercase tracking-[0.16em]" style={{ color: "#55556a" }}>
                🏆 Hall of Fame
              </p>
              {leaderboardQuery.isPending ? (
                <p className="text-xs" style={{ color: "#55556a" }}>
                  Loading…
                </p>
              ) : leaderboardQuery.data?.participants.length === 0 ? (
                <p className="text-xs" style={{ color: "#55556a" }}>
                  No entries yet — be the first!
                </p>
              ) : (
                <div className="space-y-1">
                  {leaderboardQuery.data?.participants.map((entry) => {
                    const isMe = entry.user_id === leaderboardQuery.data.my_progress !== null
                      ? undefined
                      : undefined;
                    const isMine = entry.rank === leaderboardQuery.data?.my_rank &&
                      entry.progress === leaderboardQuery.data?.my_progress;
                    const barPct = Math.min(100, Math.round((entry.progress / Math.max(entry.target, 1)) * 100));

                    return (
                      <div
                        key={entry.user_id}
                        className="flex items-center gap-2 rounded-xl px-3 py-2"
                        style={
                          isMine
                            ? { background: "rgba(251,191,36,0.08)", border: "1px solid rgba(251,191,36,0.2)" }
                            : { background: "#111118" }
                        }
                      >
                        <span className="w-5 shrink-0 text-[11px] font-bold" style={{ color: "#55556a" }}>
                          {entry.rank}
                        </span>
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center justify-between gap-2">
                            <span className="truncate text-xs font-medium" style={{ color: isMine ? "#fbbf24" : "#F0EDF8" }}>
                              {entry.nickname ?? "Athlete"}
                              {isMine ? " (you)" : ""}
                            </span>
                            <span className="shrink-0 text-[11px]" style={{ color: "#8888aa" }}>
                              {entry.progress} pts
                            </span>
                          </div>
                          <div className="mt-1 h-1 overflow-hidden rounded-full" style={{ background: "#1a1a28" }}>
                            <div
                              className="h-full rounded-full"
                              style={{ width: `${barPct}%`, background: entry.completed_at ? "#4ade80" : "#d95d39" }}
                            />
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          ) : null}
        </div>
      ) : null}
    </article>
  );
}
```

- [ ] **Step 2: Update `landing-page.tsx` to use `ChallengeCard`**

Add import at the top:
```tsx
import { ChallengeCard } from "@/components/workouts/ChallengeCard";
```

Find the challenge map block (lines ~271–299) and replace with:

```tsx
landing.gamification.active_challenges.map((challenge) => (
  <ChallengeCard key={challenge.id} challenge={challenge} />
))
```

- [ ] **Step 3: Update `realtime-sync-bridge.tsx` to handle `challenge_progress_advanced`**

In the `handleSync` function where scopes are processed, find where `landing` scope is handled and ensure `challenge_progress_advanced` reason also triggers landing invalidation.

The current code in `realtime-sync-bridge.tsx` processes the `USER_SYNC_EVENT` scopes. Since `BroadcastUserSync.for_user(user_id, ["landing"], reason: "challenge_progress_advanced", ...)` uses scope `"landing"`, it will already trigger `invalidateQueries({ queryKey: ["landing"] })` via the existing `landing` scope handler. No additional change needed to the sync bridge.

Verify by checking:
```bash
grep -n "landing" apps/web/src/components/realtime-sync-bridge.tsx
```

Confirm the `landing` scope already calls `queryClient.invalidateQueries({ queryKey: ["landing"] })`.

- [ ] **Step 4: TypeScript compile check**

```bash
cd apps/web && npx tsc --noEmit 2>&1 | head -20
```

Expected: 0 errors.

- [ ] **Step 5: Commit**

```bash
git add apps/web/src/components/workouts/ChallengeCard.tsx \
        apps/web/src/components/landing-page.tsx \
        apps/web/src/components/realtime-sync-bridge.tsx
git commit -m "feat(web): ChallengeCard — Hall of Fame leaderboard, opt-in toggle, progress event text, completions remaining"
```

---

## Task 14: Integration Test + Final Compile

- [ ] **Step 1: Run full Elixir test suite**

```bash
cd apps/api && MIX_ENV=test mix test --timeout 60000 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 2: Verify Docker API is healthy**

```bash
docker exec milos-api-1 sh -c "cd /app && mix ecto.migrate" && docker ps --format "table {{.Names}}\t{{.Status}}" | grep api
```

Expected: migration already applied (0 pending), API container shows healthy.

- [ ] **Step 3: TypeScript full check**

```bash
cd apps/web && npx tsc --noEmit
```

Expected: 0 errors.

- [ ] **Step 4: Final commit — ADR update**

Add implementation notes to the spec doc:
- No new tracking table needed: workout type stats computed in-memory from `completed_executions` + `workout_lookup`.
- `team_workout_count_fn` is a closure evaluated lazily per challenge to avoid N DB queries.
- Backward compat: challenges with `increment_per_completion` (no `rules`) continue working unchanged through all code paths.
- `completions_remaining` uses max-possible-per-completion (sum of all rules' points) as denominator — optimistic estimate.

```bash
git add -A
git commit -m "docs: update custom challenge hardening spec with implementation notes"
```

---

## Self-Review Checklist

- [x] **GetLandingPage bug fix** — Task 8 replaces raw `Map.get` with `ChallengeProgress.target/1`
- [x] **`increment_per_completion` exposed** — Task 8 adds to landing payload
- [x] **`completions_remaining` computed field** — Task 8, formula in spec
- [x] **`last_progress_event` persisted** — Task 5 (store), Task 7 (write), Task 8 (read)
- [x] **Hall of Fame opt-in/out** — Tasks 5–6 (schema), 9–10 (services + routes), 13 (UI)
- [x] **Progress capping when opted-out** — Task 7, `persist_challenge_progress`
- [x] **Leaderboard expandable on landing page** — Task 13
- [x] **Rich rules engine** — Tasks 2–4 (domain), Task 7 (wired in completion)
- [x] **`workout_type`, `scale_level`, `pr_beaten`, `weekly_consistency`, `rare_workout_type`, `team_workout_streak`** — all in Task 2 `ChallengeRule`
- [x] **Admin rules builder** — Task 12
- [x] **`criteriaSummary` improved** — Task 12
- [x] **`min={1}` on points inputs** — Task 12
- [x] **Participant table: completions_done/remaining** — Tasks 9 (backend), 12 (frontend)
- [x] **`challenge_increments` broadcast** — Task 7 (return value), Task 9 (`CompleteWorkout`)
- [x] **Realtime sync bridge** — Task 13 (existing `landing` scope already handles it)
- [x] **Migrations run in Docker** — Task 1
