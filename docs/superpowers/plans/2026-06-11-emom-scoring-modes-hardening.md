# EMOM / Complex EMOM Scoring Modes Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement four distinct scoring modes (For Time, For Quality, AMRAP, To Failure) for EMOM and Complex EMOM workout section formats, with full backend validation, timer sequencing, score calculation, creation UI, and execution UI support.

**Architecture:** `scoring_mode` is added to `timer_config` (backend) because it affects timer execution behavior (especially "To Failure" which needs open-ended rounds). On the frontend, it is stored as a dedicated `emomScoringMode` field on `DraftSection` — NOT inside `formatParams` — because `FormatParams = Record<string, number | null>` and `scoring_mode` is a string. The full score calculation path is: `timer_config.scoring_mode` → `TimerSequenceBuilder` (segment count/kind) → `ProgressSnapshotter` (snapshot derivation) → `ScoreModal` (UI rendering).

**Tech Stack:** Elixir/Phoenix (backend domain + tests), TypeScript/React/Next.js (frontend), ExUnit, Zustand store.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `apps/api/lib/milos_training/workouts/domain/timer_config.ex` | Modify | Validate `scoring_mode`, `amrap_scoring_style`, `max_windows` |
| `apps/api/lib/milos_training/execution/domain/timer_sequence_builder.ex` | Modify | Use `max_windows` for "to_failure" mode; full interval per round |
| `apps/api/lib/milos_training/execution/domain/progress_snapshotter.ex` | Modify | Dedicated EMOM snapshot logic per scoring mode |
| `apps/api/test/milos_training/workouts/domain/timer_config_test.exs` | Modify | Tests for new field validation |
| `apps/api/test/milos_training/execution/domain/timer_sequence_builder_test.exs` | Create | Tests for EMOM segment generation per mode |
| `apps/api/test/milos_training/execution/domain/progress_snapshotter_test.exs` | Modify | EMOM snapshot tests for all 4 modes |
| `apps/web/src/types/workout.ts` | Modify | `EmomScoringMode` type, new `ScoreType` values, `DraftSection` fields |
| `apps/web/src/stores/workout-creation.ts` | Modify | Parse/serialize `emomScoringMode`, `emomAmrapScoringStyle` |
| `apps/web/src/components/workouts/creation/SectionConfig.tsx` | Modify | Scoring mode picker UI for EMOM formats |
| `apps/web/src/components/workouts/execution/ScoreModal.tsx` | Modify | Pass/Fail toggle for `pass_fail` score type |

---

## Task 1: Backend — TimerConfig validation for new fields

**Files:**
- Modify: `apps/api/lib/milos_training/workouts/domain/timer_config.ex`
- Modify: `apps/api/test/milos_training/workouts/domain/timer_config_test.exs`

### Context

Currently EMOM/complex_emom timer configs have no `scoring_mode`, `amrap_scoring_style`, or `max_windows` fields. The `build_config/2` function whitelists keys via `required_fields + optional_fields`. We need to:
1. Add these three fields to `optional_fields` for the relevant types
2. Validate that `scoring_mode` is one of four permitted values
3. Validate that `amrap_scoring_style` (complex_emom only) is one of two permitted values
4. Pass these through to the stored JSONB

- [ ] **Step 1: Write the failing tests**

Add to `apps/api/test/milos_training/workouts/domain/timer_config_test.exs`:

```elixir
describe "emom scoring_mode" do
  test "accepts all valid scoring modes" do
    base = %{"type" => "emom", "duration_seconds" => 600, "interval_seconds" => 60}

    for mode <- ~w(for_time for_quality amrap to_failure) do
      assert {:ok, config} = TimerConfig.normalize(Map.put(base, "scoring_mode", mode))
      assert config.scoring_mode == mode
    end
  end

  test "rejects unknown scoring mode" do
    base = %{"type" => "emom", "duration_seconds" => 600, "interval_seconds" => 60}
    assert {:error, reason} = TimerConfig.normalize(Map.put(base, "scoring_mode", "banana"))
    assert reason =~ "scoring_mode"
  end

  test "allows missing scoring_mode (defaults to nil)" do
    assert {:ok, config} =
             TimerConfig.normalize(%{
               "type" => "emom",
               "duration_seconds" => 600,
               "interval_seconds" => 60
             })
    refute Map.has_key?(config, :scoring_mode)
  end

  test "accepts max_windows for to_failure mode" do
    assert {:ok, config} =
             TimerConfig.normalize(%{
               "type" => "emom",
               "duration_seconds" => 600,
               "interval_seconds" => 60,
               "scoring_mode" => "to_failure",
               "max_windows" => 50
             })
    assert config.max_windows == 50
  end
end

describe "complex_emom scoring_mode and amrap_scoring_style" do
  test "accepts amrap_scoring_style values" do
    base = %{
      "type" => "complex_emom",
      "duration_seconds" => 600,
      "interval_seconds" => 60,
      "scoring_mode" => "amrap"
    }

    for style <- ~w(grand_total lowest_window) do
      assert {:ok, config} = TimerConfig.normalize(Map.put(base, "amrap_scoring_style", style))
      assert config.amrap_scoring_style == style
    end
  end

  test "rejects invalid amrap_scoring_style" do
    assert {:error, reason} =
             TimerConfig.normalize(%{
               "type" => "complex_emom",
               "duration_seconds" => 600,
               "interval_seconds" => 60,
               "amrap_scoring_style" => "biggest_number"
             })
    assert reason =~ "amrap_scoring_style"
  end

  test "allows missing amrap_scoring_style" do
    assert {:ok, _config} =
             TimerConfig.normalize(%{
               "type" => "complex_emom",
               "duration_seconds" => 600,
               "interval_seconds" => 60
             })
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd apps/api && mix test test/milos_training/workouts/domain/timer_config_test.exs
```

Expected: failures about `scoring_mode` not being preserved, `amrap_scoring_style` not validated.

- [ ] **Step 3: Implement the changes**

Replace the full `timer_config.ex` with:

```elixir
defmodule MilosTraining.Workouts.Domain.TimerConfig do
  @moduledoc """
  Pure validation and normalization for workout section timer configuration.
  """

  @types ~w(
    untimed for_time train_to_exhaustion kcal_target
    emom complex_emom even_odd billat
    amrap edt death_by
    tabata custom_hiit cluster hrr
    ladder_ascending ladder_descending pyramid
    rest
  )

  @scoring_modes ~w(for_time for_quality amrap to_failure)
  @amrap_scoring_styles ~w(grand_total lowest_window)

  def normalize(nil), do: {:ok, %{type: "untimed"}}

  def normalize(config) when is_map(config) do
    type = config |> get_value(:type) |> normalize_type()

    with :ok <- validate_type(type),
         :ok <- validate_required_fields(type, config),
         :ok <- validate_scoring_mode(type, config),
         :ok <- validate_amrap_scoring_style(type, config) do
      {:ok, build_config(type, config)}
    end
  end

  def normalize(_config), do: {:error, "must be an object"}

  defp validate_type(type) do
    if type in @types, do: :ok, else: {:error, "has unsupported timer type"}
  end

  defp validate_required_fields(type, config) do
    missing =
      Enum.filter(required_fields(type), fn field ->
        config |> get_value(field) |> blank?()
      end)

    case missing do
      [] ->
        :ok

      fields ->
        {:error,
         "is missing required fields for this timer type: #{Enum.map_join(fields, ", ", &Atom.to_string/1)}"}
    end
  end

  defp validate_scoring_mode(type, config) when type in ["emom", "complex_emom"] do
    mode = get_value(config, :scoring_mode)

    cond do
      is_nil(mode) -> :ok
      mode in @scoring_modes -> :ok
      true -> {:error, "scoring_mode must be one of: #{Enum.join(@scoring_modes, ", ")}"}
    end
  end

  defp validate_scoring_mode(_type, _config), do: :ok

  defp validate_amrap_scoring_style("complex_emom", config) do
    style = get_value(config, :amrap_scoring_style)

    cond do
      is_nil(style) -> :ok
      style in @amrap_scoring_styles -> :ok
      true -> {:error, "amrap_scoring_style must be one of: #{Enum.join(@amrap_scoring_styles, ", ")}"}
    end
  end

  defp validate_amrap_scoring_style(_type, _config), do: :ok

  defp required_fields("untimed"), do: []
  defp required_fields("for_time"), do: []
  defp required_fields("train_to_exhaustion"), do: []
  defp required_fields("kcal_target"), do: []
  defp required_fields("emom"), do: [:duration_seconds, :interval_seconds]
  defp required_fields("complex_emom"), do: [:duration_seconds, :interval_seconds]
  defp required_fields("even_odd"), do: [:duration_seconds]
  defp required_fields("billat"), do: [:work_seconds, :rest_seconds, :cycles]
  defp required_fields("amrap"), do: [:duration_seconds]
  defp required_fields("edt"), do: [:duration_seconds]
  defp required_fields("death_by"), do: [:start_reps, :step_reps]
  defp required_fields("tabata"), do: [:work_seconds, :rest_seconds, :rounds]
  defp required_fields("custom_hiit"), do: [:work_seconds, :rest_seconds, :rounds]
  defp required_fields("cluster"), do: [:intra_rest_seconds, :sets]
  defp required_fields("hrr"), do: [:effort_seconds]
  defp required_fields("ladder_ascending"), do: [:start_reps, :step_reps]
  defp required_fields("ladder_descending"), do: [:start_reps, :step_reps, :min_reps]
  defp required_fields("pyramid"), do: [:peak_reps, :step_reps]
  defp required_fields("rest"), do: [:duration_seconds]

  defp optional_fields("for_time"), do: [:time_cap_seconds]
  defp optional_fields("train_to_exhaustion"), do: [:rest_seconds]
  defp optional_fields("kcal_target"), do: [:kcal_target, :time_cap_seconds]
  defp optional_fields("emom"), do: [:scoring_mode, :max_windows]
  defp optional_fields("complex_emom"), do: [:scoring_mode, :amrap_scoring_style, :max_windows]
  defp optional_fields("edt"), do: [:pr_zone_rounds]
  defp optional_fields("death_by"), do: [:ladder_cap]
  defp optional_fields("ladder_ascending"), do: [:ladder_cap]
  defp optional_fields("hrr"), do: [:hr_zone]
  defp optional_fields(_type), do: []

  defp build_config(type, config) do
    Enum.reduce(required_fields(type) ++ optional_fields(type), %{type: type}, fn key, acc ->
      case get_value(config, key) do
        nil -> acc
        "" -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp get_value(config, key), do: Map.get(config, key) || Map.get(config, Atom.to_string(key))

  defp normalize_type(nil), do: "untimed"
  defp normalize_type(type) when is_atom(type), do: type |> Atom.to_string() |> String.trim()
  defp normalize_type(type), do: type |> to_string() |> String.trim()

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
```

- [ ] **Step 4: Run tests**

```bash
cd apps/api && mix test test/milos_training/workouts/domain/timer_config_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Format and lint**

```bash
cd apps/api && mix format lib/milos_training/workouts/domain/timer_config.ex && mix credo --strict lib/milos_training/workouts/domain/timer_config.ex
```

Expected: no warnings or errors.

- [ ] **Step 6: Commit**

```bash
git add apps/api/lib/milos_training/workouts/domain/timer_config.ex \
        apps/api/test/milos_training/workouts/domain/timer_config_test.exs
git commit -m "feat(timer): add scoring_mode, amrap_scoring_style, max_windows to EMOM timer config"
```

---

## Task 2: Backend — TimerSequenceBuilder for "to_failure" mode

**Files:**
- Modify: `apps/api/lib/milos_training/execution/domain/timer_sequence_builder.ex`
- Create: `apps/api/test/milos_training/execution/domain/timer_sequence_builder_test.exs`

### Context

Currently `build_emom_segments/2` derives `total_rounds = ceil(duration / interval)`. For "to_failure" mode, there is no fixed duration — the athlete continues until failure. We use `max_windows` (default 100) as the round cap, and each round gets the full `interval_seconds` (not capped by a total duration).

The key change: when `scoring_mode = "to_failure"`, pass `effective_duration = 0` to `interval_duration/3`. The existing `interval_duration/3` already returns `interval` when `duration <= 0`, so this is a no-op for the existing function.

- [ ] **Step 1: Write the failing tests**

Create `apps/api/test/milos_training/execution/domain/timer_sequence_builder_test.exs`:

```elixir
defmodule MilosTraining.Execution.Domain.TimerSequenceBuilderTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Execution.Domain.TimerSequenceBuilder

  defp section(timer_config, exercises \\ []) do
    %{
      id: "section-1",
      name: "Main Set",
      order: 1,
      parent_section_id: nil,
      scoreable: true,
      score_config: nil,
      timer_config: timer_config,
      exercises: exercises
    }
  end

  defp workout(sections), do: %{sections: sections}

  test "emom AMRAP mode: generates ceil(duration/interval) segments" do
    s = section(%{
      type: "emom",
      duration_seconds: 300,
      interval_seconds: 60,
      scoring_mode: "amrap"
    })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert length(segments) == 5
    assert Enum.all?(segments, &(&1.duration_seconds == 60))
    assert Enum.all?(segments, &(&1.kind == :countdown))
  end

  test "emom to_failure mode: generates max_windows segments each at full interval" do
    s = section(%{
      type: "emom",
      duration_seconds: 300,
      interval_seconds: 60,
      scoring_mode: "to_failure",
      max_windows: 20
    })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert length(segments) == 20
    assert Enum.all?(segments, &(&1.duration_seconds == 60))
  end

  test "emom to_failure mode: defaults to 100 max_windows when not specified" do
    s = section(%{
      type: "emom",
      duration_seconds: 0,
      interval_seconds: 60,
      scoring_mode: "to_failure"
    })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert length(segments) == 100
  end

  test "emom for_time mode: generates same segment count as amrap" do
    s = section(%{
      type: "emom",
      duration_seconds: 600,
      interval_seconds: 60,
      scoring_mode: "for_time"
    })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert length(segments) == 10
    assert Enum.all?(segments, &(&1.duration_seconds == 60))
  end

  test "emom for_quality mode: generates same segment count as amrap" do
    s = section(%{
      type: "emom",
      duration_seconds: 600,
      interval_seconds: 60,
      scoring_mode: "for_quality"
    })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert length(segments) == 10
  end

  test "complex_emom to_failure mode: uses max_windows rounds" do
    s = section(%{
      type: "complex_emom",
      duration_seconds: 600,
      interval_seconds: 60,
      scoring_mode: "to_failure",
      max_windows: 15
    })

    segments = TimerSequenceBuilder.build(workout([s]))
    assert length(segments) == 15
    assert Enum.all?(segments, &(&1.duration_seconds == 60))
  end

  test "emom labels each segment Min N" do
    s = section(%{
      type: "emom",
      duration_seconds: 180,
      interval_seconds: 60
    })

    segments = TimerSequenceBuilder.build(workout([s]))
    labels = Enum.map(segments, & &1.label)
    assert labels == ["Min 1", "Min 2", "Min 3"]
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd apps/api && mix test test/milos_training/execution/domain/timer_sequence_builder_test.exs
```

Expected: failures — `to_failure` tests fail because `max_windows` is ignored.

- [ ] **Step 3: Implement the change**

In `apps/api/lib/milos_training/execution/domain/timer_sequence_builder.ex`, replace `build_emom_segments/2`:

```elixir
defp build_emom_segments(section, exercises) do
  duration = get_timer_field(section, :duration_seconds) || 0
  interval = get_timer_field(section, :interval_seconds) || 60
  scoring_mode = get_timer_field(section, :scoring_mode) || "amrap"
  max_windows = get_timer_field(section, :max_windows) || 100

  {total_rounds, effective_duration} =
    cond do
      scoring_mode == "to_failure" ->
        {max_windows, 0}

      interval > 0 and duration > 0 ->
        {max(ceil(duration / interval), 1), duration}

      true ->
        {1, duration}
    end

  Enum.map(1..total_rounds, fn round ->
    round_exercises =
      if exercises == [] do
        []
      else
        round_exercises_for_emom(exercises, round, total_rounds)
      end

    segment(
      section,
      :countdown,
      interval_duration(effective_duration, interval, round),
      round,
      total_rounds,
      round_exercises,
      label: "Min #{round}"
    )
  end)
end
```

- [ ] **Step 4: Run tests**

```bash
cd apps/api && mix test test/milos_training/execution/domain/timer_sequence_builder_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Format and lint**

```bash
cd apps/api && mix format lib/milos_training/execution/domain/timer_sequence_builder.ex && mix credo --strict lib/milos_training/execution/domain/timer_sequence_builder.ex
```

- [ ] **Step 6: Commit**

```bash
git add apps/api/lib/milos_training/execution/domain/timer_sequence_builder.ex \
        apps/api/test/milos_training/execution/domain/timer_sequence_builder_test.exs
git commit -m "feat(timer): handle to_failure mode with max_windows in EMOM segment builder"
```

---

## Task 3: Backend — ProgressSnapshotter EMOM scoring mode dispatch

**Files:**
- Modify: `apps/api/lib/milos_training/execution/domain/progress_snapshotter.ex`
- Modify: `apps/api/test/milos_training/execution/domain/progress_snapshotter_test.exs`

### Context

Currently `emom`/`complex_emom` fall through to `generic_progress_snapshot` in both progress and final paths. We need dedicated dispatch for all 4 scoring modes:

| Mode | Progress score | Final score |
|------|---------------|-------------|
| `for_time` | elapsed time (section_elapsed_ms) | accumulated work time (same) |
| `for_quality` | intervals completed count | "Pass" if all completed, else "Fail" |
| `amrap` | total reps across all windows | total reps (same) |
| `to_failure` | intervals survived (cycle_count > 0) | intervals survived (same) |

For Complex EMOM AMRAP with `amrap_scoring_style: "lowest_window"`, the final score is the minimum reps scored in any single window (not the sum).

- [ ] **Step 1: Write the failing tests**

Add to `apps/api/test/milos_training/execution/domain/progress_snapshotter_test.exs`:

```elixir
# Helper: build an EMOM segment for testing
defp emom_segment(segment_key, section_id, scoring_mode, exercises, opts \\ []) do
  %{
    segment_key: segment_key,
    section_id: section_id,
    section_name: "EMOM",
    format: Keyword.get(opts, :format, "emom"),
    kind: :countdown,
    scoreable: true,
    score_config: nil,
    timer_config: Map.merge(
      %{
        type: Keyword.get(opts, :format, "emom"),
        duration_seconds: 600,
        interval_seconds: 60,
        scoring_mode: scoring_mode
      },
      Keyword.get(opts, :timer_config_extra, %{})
    ),
    exercises: exercises
  }
end

describe "EMOM for_time mode" do
  test "progress: derives elapsed time from section_elapsed_ms" do
    segments = [
      emom_segment("seg:0", "sec-1", "for_time", []),
      emom_segment("seg:1", "sec-1", "for_time", [])
    ]

    state = %{
      checked_exercise_ids: [],
      section_elapsed_ms: %{"sec-1" => 75_000},
      segment_cycle_counts: %{}
    }

    assert [%{section_id: "sec-1", value: "1:15", score_type: "accumulated_work_time", kind: "progress"}] =
             ProgressSnapshotter.progress_snapshots(segments, state)
  end

  test "final: derives accumulated_work_time" do
    segments = [emom_segment("seg:0", "sec-1", "for_time", [])]

    state = %{
      checked_exercise_ids: [],
      section_elapsed_ms: %{"sec-1" => 95_000},
      segment_cycle_counts: %{}
    }

    assert [%{section_id: "sec-1", value: "1:35", score_type: "accumulated_work_time", kind: "final"}] =
             ProgressSnapshotter.final_snapshots(segments, state, [])
  end
end

describe "EMOM for_quality mode" do
  test "progress: counts completed intervals" do
    segments = [
      emom_segment("seg:0", "sec-q", "for_quality", []),
      emom_segment("seg:1", "sec-q", "for_quality", [])
    ]

    state = %{
      checked_exercise_ids: [],
      section_elapsed_ms: %{},
      segment_cycle_counts: %{"seg:0" => 1}
    }

    assert [%{section_id: "sec-q", value: 1, unit: "intervals", kind: "progress"}] =
             ProgressSnapshotter.progress_snapshots(segments, state)
  end

  test "final: Pass when all intervals completed" do
    segments = [
      emom_segment("seg:0", "sec-q", "for_quality", []),
      emom_segment("seg:1", "sec-q", "for_quality", [])
    ]

    state = %{
      checked_exercise_ids: [],
      section_elapsed_ms: %{},
      segment_cycle_counts: %{"seg:0" => 1, "seg:1" => 1}
    }

    assert [%{section_id: "sec-q", value: "Pass", score_type: "pass_fail", kind: "final"}] =
             ProgressSnapshotter.final_snapshots(segments, state, [])
  end

  test "final: Fail when any interval not completed" do
    segments = [
      emom_segment("seg:0", "sec-q", "for_quality", []),
      emom_segment("seg:1", "sec-q", "for_quality", [])
    ]

    state = %{
      checked_exercise_ids: [],
      section_elapsed_ms: %{},
      segment_cycle_counts: %{"seg:0" => 1}
    }

    assert [%{section_id: "sec-q", value: "Fail", score_type: "pass_fail", kind: "final"}] =
             ProgressSnapshotter.final_snapshots(segments, state, [])
  end
end

describe "EMOM amrap mode" do
  test "progress and final: total cumulative reps across all windows" do
    ex = %{id: "ex-1", name: "Thrusters", sets: 1, prescription_value: 10}

    segments = [
      emom_segment("seg:0", "sec-a", "amrap", [ex]),
      emom_segment("seg:1", "sec-a", "amrap", [ex])
    ]

    state = %{
      checked_exercise_ids: [],
      section_elapsed_ms: %{},
      segment_cycle_counts: %{"seg:0" => 3, "seg:1" => 2}
    }

    assert [%{section_id: "sec-a", value: 50, unit: "reps", score_type: "reps", kind: "progress"}] =
             ProgressSnapshotter.progress_snapshots(segments, state)
  end
end

describe "EMOM to_failure mode" do
  test "progress and final: intervals survived = segments with cycle_count > 0" do
    segments = [
      emom_segment("seg:0", "sec-f", "to_failure", []),
      emom_segment("seg:1", "sec-f", "to_failure", []),
      emom_segment("seg:2", "sec-f", "to_failure", [])
    ]

    state = %{
      checked_exercise_ids: [],
      section_elapsed_ms: %{},
      segment_cycle_counts: %{"seg:0" => 1, "seg:1" => 1}
    }

    assert [%{section_id: "sec-f", value: 2, unit: "intervals", score_type: "intervals_survived", kind: "progress"}] =
             ProgressSnapshotter.progress_snapshots(segments, state)

    assert [%{section_id: "sec-f", value: 2, unit: "intervals", score_type: "intervals_survived", kind: "final"}] =
             ProgressSnapshotter.final_snapshots(segments, state, [])
  end
end

describe "Complex EMOM AMRAP lowest_window mode" do
  test "final: score is the lowest window rep count, not grand total" do
    ex = %{id: "ex-1", name: "Row", sets: 1, prescription_value: 5}

    segments = [
      emom_segment("seg:0", "sec-cx", "amrap", [ex],
        format: "complex_emom",
        timer_config_extra: %{amrap_scoring_style: "lowest_window"}
      ),
      emom_segment("seg:1", "sec-cx", "amrap", [ex],
        format: "complex_emom",
        timer_config_extra: %{amrap_scoring_style: "lowest_window"}
      ),
      emom_segment("seg:2", "sec-cx", "amrap", [ex],
        format: "complex_emom",
        timer_config_extra: %{amrap_scoring_style: "lowest_window"}
      )
    ]

    # seg:0 = 4 cycles → 20 reps, seg:1 = 2 cycles → 10 reps, seg:2 = 3 cycles → 15 reps
    # lowest_window = 10
    state = %{
      checked_exercise_ids: [],
      section_elapsed_ms: %{},
      segment_cycle_counts: %{"seg:0" => 4, "seg:1" => 2, "seg:2" => 3}
    }

    assert [%{section_id: "sec-cx", value: 10, unit: "reps", score_type: "reps", kind: "final"}] =
             ProgressSnapshotter.final_snapshots(segments, state, [])
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd apps/api && mix test test/milos_training/execution/domain/progress_snapshotter_test.exs
```

Expected: all new tests fail.

- [ ] **Step 3: Implement the changes**

In `apps/api/lib/milos_training/execution/domain/progress_snapshotter.ex`, make the following changes:

**3a. Add EMOM cases in `snapshot_for_section` for `:progress`**

In the existing `case format do` block within `defp snapshot_for_section(section_segments, state, :progress, _manual_sections)`, add after the existing `"hrr"` case and before `_other`:

```elixir
"emom" ->
  emom_progress_snapshot(section_segments, state)

"complex_emom" ->
  emom_progress_snapshot(section_segments, state)
```

**3b. Add EMOM handling in `snapshot_for_section` for `:final`**

In `defp snapshot_for_section(section_segments, state, :final, manual_sections)`, wrap the existing logic to check for EMOM format first:

Replace:
```elixir
defp snapshot_for_section(section_segments, state, :final, manual_sections) do
  section_id = hd(section_segments) |> segment_section_id()

  if MapSet.member?(manual_sections, section_id) do
    nil
  else
    format = section_format(section_segments)
    score_type = final_score_type(format, score_config(section_segments))

    base =
      case score_type do
        "time" -> time_final_snapshot(section_id, state)
        "rounds+reps" -> rounds_reps_progress_snapshot(section_segments, state)
        "reps" -> reps_final_snapshot(section_segments, state, format)
        "rounds" -> rounds_progress_snapshot(section_segments, state, "rounds")
        _other -> generic_progress_snapshot(section_segments, state)
      end

    snapshot(section_id, Map.put(base, :score_type, score_type), "final", "auto")
  end
end
```

With:
```elixir
defp snapshot_for_section(section_segments, state, :final, manual_sections) do
  section_id = hd(section_segments) |> segment_section_id()

  if MapSet.member?(manual_sections, section_id) do
    nil
  else
    format = section_format(section_segments)

    base =
      if format in ["emom", "complex_emom"] do
        emom_final_snapshot(section_segments, state)
      else
        score_type = final_score_type(format, score_config(section_segments))

        result =
          case score_type do
            "time" -> time_final_snapshot(section_id, state)
            "rounds+reps" -> rounds_reps_progress_snapshot(section_segments, state)
            "reps" -> reps_final_snapshot(section_segments, state, format)
            "rounds" -> rounds_progress_snapshot(section_segments, state, "rounds")
            _other -> generic_progress_snapshot(section_segments, state)
          end

        result && Map.put(result, :score_type, score_type)
      end

    snapshot(section_id, base, "final", "auto")
  end
end
```

**3c. Add the EMOM helper functions** (add before the `# ── Helpers ──` section):

```elixir
# ── EMOM: scoring-mode-aware snapshots ────────────────────────────────────────

defp emom_scoring_mode(section_segments) do
  timer_config = hd(section_segments) |> get_in_segment(:timer_config)
  timer_config[:scoring_mode] || timer_config["scoring_mode"] || "amrap"
end

defp emom_amrap_scoring_style(section_segments) do
  timer_config = hd(section_segments) |> get_in_segment(:timer_config)
  timer_config[:amrap_scoring_style] || timer_config["amrap_scoring_style"] || "grand_total"
end

defp emom_progress_snapshot(section_segments, state) do
  section_id = hd(section_segments) |> segment_section_id()

  case emom_scoring_mode(section_segments) do
    "for_time" ->
      case section_elapsed_ms(state, section_id) do
        elapsed when elapsed > 0 ->
          %{value: format_duration(elapsed), score_type: "accumulated_work_time"}
        _ -> nil
      end

    "for_quality" ->
      survived = Enum.count(section_segments, &(completed_cycles(&1, state) > 0))
      if survived > 0, do: %{value: survived, unit: "intervals", score_type: "intervals_survived"}, else: nil

    "amrap" ->
      reps_progress_snapshot(section_segments, state)

    "to_failure" ->
      survived = Enum.count(section_segments, &(completed_cycles(&1, state) > 0))
      if survived > 0, do: %{value: survived, unit: "intervals", score_type: "intervals_survived"}, else: nil

    _ ->
      reps_progress_snapshot(section_segments, state)
  end
end

defp emom_final_snapshot(section_segments, state) do
  section_id = hd(section_segments) |> segment_section_id()
  format = section_format(section_segments)

  case emom_scoring_mode(section_segments) do
    "for_time" ->
      case section_elapsed_ms(state, section_id) do
        elapsed when elapsed > 0 ->
          %{value: format_duration(elapsed), score_type: "accumulated_work_time"}
        _ -> nil
      end

    "for_quality" ->
      total = length(section_segments)
      survived = Enum.count(section_segments, &(completed_cycles(&1, state) > 0))
      result = if survived >= total, do: "Pass", else: "Fail"
      %{value: result, score_type: "pass_fail"}

    "amrap" when format == "complex_emom" ->
      case emom_amrap_scoring_style(section_segments) do
        "lowest_window" ->
          # Score = minimum per-window reps (competitive scoring)
          window_reps =
            Enum.map(section_segments, fn seg ->
              completed_cycles(seg, state) * cycle_reps(seg)
            end)

          case Enum.filter(window_reps, &(&1 > 0)) do
            [] -> nil
            nonzero -> %{value: Enum.min(nonzero), unit: "reps", score_type: "reps"}
          end

        _ ->
          reps_progress_snapshot(section_segments, state)
      end

    "amrap" ->
      reps_progress_snapshot(section_segments, state)

    "to_failure" ->
      survived = Enum.count(section_segments, &(completed_cycles(&1, state) > 0))
      if survived > 0, do: %{value: survived, unit: "intervals", score_type: "intervals_survived"}, else: nil

    _ ->
      reps_progress_snapshot(section_segments, state)
  end
end

defp get_in_segment(segment, key) do
  segment[key] || segment[Atom.to_string(key)] || %{}
end
```

- [ ] **Step 4: Run tests**

```bash
cd apps/api && mix test test/milos_training/execution/domain/progress_snapshotter_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Run the full test suite**

```bash
cd apps/api && mix test
```

Expected: all existing tests still pass.

- [ ] **Step 6: Format and lint**

```bash
cd apps/api && mix format lib/milos_training/execution/domain/progress_snapshotter.ex && mix credo --strict lib/milos_training/execution/domain/progress_snapshotter.ex
```

- [ ] **Step 7: Commit**

```bash
git add apps/api/lib/milos_training/execution/domain/progress_snapshotter.ex \
        apps/api/test/milos_training/execution/domain/progress_snapshotter_test.exs
git commit -m "feat(scoring): implement EMOM scoring mode dispatch in ProgressSnapshotter"
```

---

## Task 4: Frontend — Types, new ScoreType values, DraftSection fields

**Files:**
- Modify: `apps/web/src/types/workout.ts`

### Context

`FormatParams = Record<string, number | null>` — it cannot hold strings. `scoring_mode` and `amrap_scoring_style` are strings. They must live as **dedicated fields on `DraftSection`**, not in `formatParams`. This is the same pattern as how `scoreable` and `scoreType` already exist as dedicated fields rather than being stuffed into `formatParams`.

`max_windows` IS a number, so it stays in `formatParams` (added to `FORMAT_FIELD_DEFS`).

- [ ] **Step 1: Add `EmomScoringMode` type and update `ScoreType`**

In `apps/web/src/types/workout.ts`:

After the existing `export type ScoreType = ...` definition, replace it with:

```typescript
export type ScoreType =
  | "time"
  | "reps"
  | "weight"
  | "rounds"
  | "rounds+reps"
  | "kcal"
  | "hr_drop"
  | "load"
  | "accumulated_work_time"
  | "pass_fail"
  | "intervals_survived";
```

Add after `ScoreType`:

```typescript
export type EmomScoringMode = "for_time" | "for_quality" | "amrap" | "to_failure";

export const EMOM_SCORING_MODE_LABELS: Record<EmomScoringMode, string> = {
  for_time: "For Time",
  for_quality: "For Quality",
  amrap: "AMRAP",
  to_failure: "To Failure",
};

export const EMOM_SCORING_MODE_DESCRIPTIONS: Record<EmomScoringMode, string> = {
  for_time: "Sprint each window. Score = accumulated work time (lower is better).",
  for_quality: "Prioritize perfect form. Score = Pass / Fail.",
  amrap: "Max reps each window. Score = total cumulative reps.",
  to_failure: "Fixed reps each window, keep going until you fail. Score = windows survived.",
};

export const EMOM_SCORING_MODE_SCORE_TYPE: Record<EmomScoringMode, ScoreType> = {
  for_time: "accumulated_work_time",
  for_quality: "pass_fail",
  amrap: "reps",
  to_failure: "intervals_survived",
};
```

- [ ] **Step 2: Add `emomScoringMode` and `emomAmrapScoringStyle` to `DraftSection`**

Replace:

```typescript
export type DraftSection = {
  localId: string;
  name: string;
  format: SectionFormat;
  formatParams: FormatParams;
  scoreable: boolean;
  scoreType: ScoreType | null;
  restAfterSeconds: number | null;
  exercises: DraftExercise[];
};
```

With:

```typescript
export type DraftSection = {
  localId: string;
  name: string;
  format: SectionFormat;
  formatParams: FormatParams;
  scoreable: boolean;
  scoreType: ScoreType | null;
  restAfterSeconds: number | null;
  exercises: DraftExercise[];
  emomScoringMode: EmomScoringMode | null;
  emomAmrapScoringStyle: "grand_total" | "lowest_window" | null;
};
```

- [ ] **Step 3: Update `makeDefaultSection`**

Replace:

```typescript
export function makeDefaultSection(): DraftSection {
  return {
    localId: crypto.randomUUID(),
    name: "",
    format: "untimed",
    formatParams: {},
    scoreable: false,
    scoreType: null,
    restAfterSeconds: null,
    exercises: [],
  };
}
```

With:

```typescript
export function makeDefaultSection(): DraftSection {
  return {
    localId: crypto.randomUUID(),
    name: "",
    format: "untimed",
    formatParams: {},
    scoreable: false,
    scoreType: null,
    restAfterSeconds: null,
    exercises: [],
    emomScoringMode: null,
    emomAmrapScoringStyle: null,
  };
}
```

- [ ] **Step 4: Add `max_windows` to FORMAT_FIELD_DEFS for emom and complex_emom**

In `FORMAT_FIELD_DEFS`, update the `emom` and `complex_emom` entries:

```typescript
emom: [
  { key: "duration_seconds", defaultValue: 600, required: true },
  { key: "interval_seconds", defaultValue: 60, required: true },
  { key: "max_windows", defaultValue: 100 },
],
complex_emom: [
  { key: "duration_seconds", defaultValue: 600, required: true },
  { key: "interval_seconds", defaultValue: 60, required: true },
  { key: "max_windows", defaultValue: 100 },
],
```

- [ ] **Step 5: Update FORMAT_TOOLTIPS for emom and complex_emom**

Replace the existing `emom` and `complex_emom` entries in `FORMAT_TOOLTIPS`:

```typescript
emom: {
  bestFor: "Interval training with defined objectives",
  trains: "Power output, pacing, endurance, or technique",
  how: "Same movement every interval. Choose a mode: For Time (sprint + rest), For Quality (form focus), AMRAP (max reps), or To Failure (survive as many windows as possible).",
  score: "Accumulated work time / Pass-Fail / Total reps / Windows survived",
},
complex_emom: {
  bestFor: "Mixed modality circuit training",
  trains: "Varied skills, pacing, multi-modal conditioning",
  how: "2+ movements rotating each interval window. Choose: For Time, For Quality, AMRAP (grand total or lowest window), or To Failure.",
  score: "Accumulated work time / Pass-Fail / Total reps or lowest window / Stations cleared",
},
```

- [ ] **Step 6: TypeScript compile check**

```bash
cd apps/web && npx tsc --noEmit
```

Expected: no errors (store and components may temporarily fail until Tasks 5-6 fix them — but `types/workout.ts` alone should type-check cleanly).

- [ ] **Step 7: Commit**

```bash
git add apps/web/src/types/workout.ts
git commit -m "feat(types): add EmomScoringMode type, new ScoreType values, DraftSection EMOM fields"
```

---

## Task 5: Frontend — Store parsing and serialization

**Files:**
- Modify: `apps/web/src/stores/workout-creation.ts`

### Context

The store's `parseDraftSections` converts ALL timer_config values to numbers via `Number(v)`. `scoring_mode` and `amrap_scoring_style` are strings — they would become `NaN` if parsed this way. We extract them separately before the numeric conversion loop.

The serialization path (`timer_config: { type, ...section.formatParams }`) needs to additionally include `scoring_mode` and `amrap_scoring_style` from the new `DraftSection` fields.

- [ ] **Step 1: Update `parseScoreType` to accept new values**

Replace:

```typescript
function parseScoreType(value: unknown): ScoreType | null {
  const valid: ScoreType[] = ["time", "reps", "weight", "rounds", "rounds+reps", "kcal", "hr_drop", "load"];
  return valid.includes(value as ScoreType) ? (value as ScoreType) : null;
}
```

With:

```typescript
function parseScoreType(value: unknown): ScoreType | null {
  const valid: ScoreType[] = [
    "time", "reps", "weight", "rounds", "rounds+reps", "kcal", "hr_drop", "load",
    "accumulated_work_time", "pass_fail", "intervals_survived",
  ];
  return valid.includes(value as ScoreType) ? (value as ScoreType) : null;
}
```

- [ ] **Step 2: Add `parseEmomScoringMode` and `parseAmrapScoringStyle` helpers**

Add after `parseScoreType`:

```typescript
function parseEmomScoringMode(value: unknown): EmomScoringMode | null {
  const valid: EmomScoringMode[] = ["for_time", "for_quality", "amrap", "to_failure"];
  return valid.includes(value as EmomScoringMode) ? (value as EmomScoringMode) : null;
}

function parseAmrapScoringStyle(value: unknown): "grand_total" | "lowest_window" | null {
  return value === "grand_total" || value === "lowest_window" ? value : null;
}
```

You'll also need to add `EmomScoringMode` to the import from `@/types/workout`.

- [ ] **Step 3: Update `parseDraftSections` to extract string fields separately**

In `parseDraftSections`, replace the `formatParams` extraction block:

```typescript
// BEFORE:
const { type: _type, ...formatParamRaw } = timerConfig;
const formatParams: FormatParams = {};
for (const [k, v] of Object.entries(formatParamRaw)) {
  formatParams[k] = v != null ? Number(v) : null;
}
```

With:

```typescript
const {
  type: _type,
  scoring_mode: rawScoringMode,
  amrap_scoring_style: rawAmrapStyle,
  ...formatParamRaw
} = timerConfig;

const emomScoringMode = parseEmomScoringMode(rawScoringMode);
const emomAmrapScoringStyle = parseAmrapScoringStyle(rawAmrapStyle);

const formatParams: FormatParams = {};
for (const [k, v] of Object.entries(formatParamRaw)) {
  formatParams[k] = v != null ? Number(v) : null;
}
```

And update the returned section object to include the new fields:

```typescript
return {
  localId: crypto.randomUUID(),
  name: typeof sec.name === "string" ? sec.name : "",
  format,
  formatParams: Object.keys(formatParams).length > 0 ? formatParams : makeDefaultFormatParams(format),
  scoreable: Boolean(sec.scoreable),
  scoreType,
  restAfterSeconds: sec.rest_after_seconds != null ? Number(sec.rest_after_seconds) : null,
  exercises,
  emomScoringMode,
  emomAmrapScoringStyle,
};
```

- [ ] **Step 4: Add `setEmomScoringMode` action and update `setFormat` reset**

In the Zustand store actions, add `setEmomScoringMode`:

```typescript
setEmomScoringMode: (sectionId: string, mode: EmomScoringMode | null) => {
  set((state) => ({
    sections: state.sections.map((section) => {
      if (section.localId !== sectionId) return section;
      const scoreType = mode ? EMOM_SCORING_MODE_SCORE_TYPE[mode] : null;
      return { ...section, emomScoringMode: mode, scoreType };
    }),
  }));
},

setEmomAmrapScoringStyle: (sectionId: string, style: "grand_total" | "lowest_window" | null) => {
  set((state) => ({
    sections: state.sections.map((section) =>
      section.localId === sectionId
        ? { ...section, emomAmrapScoringStyle: style }
        : section
    ),
  }));
},
```

In the existing `setFormat` action, after resetting `formatParams`, also reset the EMOM fields when changing away from EMOM formats:

```typescript
setFormat: (sectionId: string, format: SectionFormat) => {
  const autoScore = AUTO_SCORE_MAP[format] ?? null;
  const isEmom = format === "emom" || format === "complex_emom";

  set((state) => ({
    sections: state.sections.map((section) => {
      if (section.localId !== sectionId) return section;
      return {
        ...section,
        format,
        formatParams: makeDefaultFormatParams(format),
        scoreType: autoScore,
        emomScoringMode: isEmom ? section.emomScoringMode : null,
        emomAmrapScoringStyle: isEmom ? section.emomAmrapScoringStyle : null,
      };
    }),
  }));
},
```

- [ ] **Step 5: Update serialization to include `scoring_mode` in `timer_config`**

In the section serialization block, update `timer_config`:

```typescript
timer_config: {
  type: section.format,
  ...section.formatParams,
  ...deriveLadderTimerParams(section),
  ...(section.emomScoringMode ? { scoring_mode: section.emomScoringMode } : {}),
  ...(section.emomAmrapScoringStyle ? { amrap_scoring_style: section.emomAmrapScoringStyle } : {}),
},
```

- [ ] **Step 6: TypeScript compile check**

```bash
cd apps/web && npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add apps/web/src/stores/workout-creation.ts
git commit -m "feat(store): parse and serialize emomScoringMode and emomAmrapScoringStyle"
```

---

## Task 6: Frontend — Creation UI scoring mode picker in SectionConfig

**Files:**
- Modify: `apps/web/src/components/workouts/creation/SectionConfig.tsx`

### Context

When `format === "emom"` or `format === "complex_emom"` and `scoreable === true`, show a scoring mode picker in place of the generic score type select. The picker maps to `setEmomScoringMode`. When `format === "complex_emom"` and `emomScoringMode === "amrap"`, show an additional `amrap_scoring_style` radio. When `emomScoringMode === "to_failure"`, show a `max_windows` number input (the field exists in `formatParams` via Task 4's `FORMAT_FIELD_DEFS` addition).

- [ ] **Step 1: Import new types and actions**

Update the imports in `SectionConfig.tsx`:

```typescript
import {
  useWorkoutCreationStore
} from "@/stores/workout-creation";
import {
  AUTO_SCORE_MAP,
  EMOM_SCORING_MODE_DESCRIPTIONS,
  EMOM_SCORING_MODE_LABELS,
  EMOM_SCORING_MODE_SCORE_TYPE,
  type DraftSection,
  type EmomScoringMode,
  type ScoreType,
} from "@/types/workout";
```

- [ ] **Step 2: Destructure new store actions**

```typescript
const {
  updateSection,
  setFormat,
  setFormatParams,
  setEmomScoringMode,
  setEmomAmrapScoringStyle,
  deleteSection,
} = useWorkoutCreationStore();
```

- [ ] **Step 3: Add the scoring mode picker and conditional to SectionConfig**

After the existing scoreable toggle (and before/replacing the `showScorePicker` block), add:

```typescript
const isEmomFormat = section.format === "emom" || section.format === "complex_emom";
const autoScore = AUTO_SCORE_MAP[section.format];
// For EMOM formats, scoring mode picker handles score type selection
const showScorePicker = section.scoreable && !autoScore && !isEmomFormat;
const showEmomScoringPicker = section.scoreable && isEmomFormat;
const showAmrapStyle = showEmomScoringPicker &&
  section.format === "complex_emom" &&
  section.emomScoringMode === "amrap";
const showMaxWindows = showEmomScoringPicker && section.emomScoringMode === "to_failure";
```

Then add the EMOM scoring mode picker JSX after the scoreable toggle:

```tsx
{showEmomScoringPicker ? (
  <div>
    <label
      className="mb-2 block text-xs font-bold uppercase tracking-widest"
      style={{ color: "var(--muted)" }}
    >
      Scoring Mode
    </label>
    <div className="flex flex-col gap-2">
      {(["for_time", "for_quality", "amrap", "to_failure"] as EmomScoringMode[]).map(
        (mode) => (
          <button
            key={mode}
            type="button"
            onClick={() => setEmomScoringMode(section.localId, mode)}
            className="flex flex-col gap-0.5 rounded-xl px-3 py-2 text-left transition-colors"
            style={
              section.emomScoringMode === mode
                ? {
                    background: "color-mix(in srgb, var(--accent) 15%, transparent)",
                    border: "1px solid var(--accent)",
                    color: "var(--text)",
                  }
                : {
                    background: "var(--bg)",
                    border: "1px solid var(--dim)",
                    color: "var(--muted)",
                  }
            }
          >
            <span className="text-xs font-bold">
              {EMOM_SCORING_MODE_LABELS[mode]}
            </span>
            <span className="text-xs leading-tight" style={{ color: "var(--dim)" }}>
              {EMOM_SCORING_MODE_DESCRIPTIONS[mode]}
            </span>
          </button>
        ),
      )}
    </div>
  </div>
) : null}

{showAmrapStyle ? (
  <div>
    <label
      className="mb-2 block text-xs font-bold uppercase tracking-widest"
      style={{ color: "var(--muted)" }}
    >
      AMRAP Scoring Style
    </label>
    <div className="flex gap-2">
      {(["grand_total", "lowest_window"] as const).map((style) => (
        <button
          key={style}
          type="button"
          onClick={() => setEmomAmrapScoringStyle(section.localId, style)}
          className="flex-1 rounded-xl px-3 py-2 text-xs font-bold transition-colors"
          style={
            section.emomAmrapScoringStyle === style ||
            (section.emomAmrapScoringStyle === null && style === "grand_total")
              ? {
                  background: "color-mix(in srgb, var(--accent) 15%, transparent)",
                  border: "1px solid var(--accent)",
                  color: "var(--text)",
                }
              : {
                  background: "var(--bg)",
                  border: "1px solid var(--dim)",
                  color: "var(--muted)",
                }
          }
        >
          {style === "grand_total" ? "Grand Total" : "Lowest Window"}
        </button>
      ))}
    </div>
    <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
      {section.emomAmrapScoringStyle === "lowest_window"
        ? "Score = your worst window. Punishes inconsistent pacing."
        : "Score = sum of all reps across all windows."}
    </p>
  </div>
) : null}

{showMaxWindows ? (
  <div className="flex items-center justify-between gap-2">
    <label
      className="shrink-0 text-xs font-bold uppercase tracking-widest"
      style={{ color: "var(--muted)" }}
    >
      Max Windows
    </label>
    <input
      type="number"
      min={1}
      max={200}
      value={(section.formatParams.max_windows as number) ?? 100}
      onChange={(event) =>
        setFormatParams(section.localId, {
          ...section.formatParams,
          max_windows: Number(event.target.value) || 100,
        })
      }
      className="w-20 rounded-lg px-2 py-1 text-right text-sm outline-none"
      style={{
        background: "var(--bg)",
        border: "1px solid var(--dim)",
        color: "var(--text)",
      }}
    />
  </div>
) : null}
```

- [ ] **Step 4: TypeScript compile check**

```bash
cd apps/web && npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add apps/web/src/components/workouts/creation/SectionConfig.tsx
git commit -m "feat(creation-ui): add EMOM scoring mode picker with AMRAP style and max_windows controls"
```

---

## Task 7: Frontend — ScoreModal pass/fail support

**Files:**
- Modify: `apps/web/src/components/workouts/execution/ScoreModal.tsx`

### Context

Currently `ScoreModal` renders a numeric or time text input based on `scoreType`. For `pass_fail` score type, it must render a Pass/Fail toggle button pair. The `value` stored for `pass_fail` is the string `"Pass"` or `"Fail"`.

- [ ] **Step 1: Read the current ScoreModal implementation**

Read `apps/web/src/components/workouts/execution/ScoreModal.tsx` (do this before editing).

- [ ] **Step 2: Add pass_fail rendering**

In `ScoreModal`, find where the score input is rendered. It currently checks `scoreType === "time"`, `scoreType === "reps"`, etc. Add a branch for `pass_fail` that renders a toggle:

```tsx
{scoreType === "pass_fail" ? (
  <div className="flex gap-3">
    {(["Pass", "Fail"] as const).map((option) => (
      <button
        key={option}
        type="button"
        onClick={() => setValue(option)}
        className="flex-1 rounded-2xl py-4 text-lg font-bold transition-colors"
        style={
          value === option
            ? option === "Pass"
              ? {
                  background: "color-mix(in srgb, #22c55e 20%, transparent)",
                  border: "2px solid #22c55e",
                  color: "#22c55e",
                }
              : {
                  background: "color-mix(in srgb, #ef4444 20%, transparent)",
                  border: "2px solid #ef4444",
                  color: "#ef4444",
                }
            : {
                background: "var(--bg)",
                border: "1px solid var(--dim)",
                color: "var(--muted)",
              }
        }
      >
        {option}
      </button>
    ))}
  </div>
) : /* existing input rendering here */ null}
```

The existing Save button should be disabled when `value` is empty (`value === ""`). For `pass_fail`, set an initial value of `"Pass"` (optimistic default — the athlete managed to complete the session).

In the modal initialization where `value` is set from any existing score, ensure `pass_fail` scores are accepted as strings (they likely already are since value is `string`).

- [ ] **Step 3: Set default value for pass_fail**

Wherever the modal initializes `value` (usually `useState("")` or from an existing score prop), add:

```typescript
const defaultValue = scoreType === "pass_fail" ? "Pass" : "";
const [value, setValue] = useState(existingScore?.value ?? defaultValue);
```

- [ ] **Step 4: TypeScript compile check**

```bash
cd apps/web && npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 5: Run the full backend test suite one more time**

```bash
cd apps/api && mix test
```

Expected: all tests pass.

- [ ] **Step 6: Final commit**

```bash
git add apps/web/src/components/workouts/execution/ScoreModal.tsx
git commit -m "feat(execution-ui): add Pass/Fail toggle to ScoreModal for for_quality EMOM scoring"
```

---

## Task 8: Frontend — computeMeasuredScore EMOM cases

**Files:**
- Modify: `apps/web/src/components/workouts/execution/progress.ts`

### Context

`computeMeasuredScore` in `progress.ts` is a pre-fill fallback for the ScoreModal — it runs client-side before the backend's `ProgressSnapshotter` result arrives. It currently has no `emom`/`complex_emom` cases and falls through to the `default` branch (which only returns a value if `score_config.type === "time"`).

**Design constraint:** The function receives a single `TimerSegment` and `ProgressState`. For EMOM, each window is its own segment (`segment_key: "segment:N"`), and `segmentCycleCounts` is keyed by `segment_key`. Without the full list of segment_keys for the section, cross-window aggregation (total reps for AMRAP, total windows for To Failure) is impossible.

**Consequence:** 
- `for_time` → use `sectionElapsedMs[section_id]` (total section elapsed time, shared across all windows) — reasonable approximation.
- `for_quality` → pre-fill `"Pass"` (athlete reached ScoreModal = completed the session).
- `amrap` / `to_failure` → return `null` (backend `ProgressSnapshotter` provides the accurate score).

This is intentional and safe: `computeMeasuredScore` is only used when `existingScore?.kind === "final"` is absent (see `ExecutionMode.tsx:790`).

- [x] **Step 1: Add EMOM case to `computeMeasuredScore`**

In `apps/web/src/components/workouts/execution/progress.ts`, replace:

```typescript
  switch (segment.format) {
    case "for_time":
```

With:

```typescript
  switch (segment.format) {
    case "emom":
    case "complex_emom": {
      const scoringMode = String(segment.timer_config?.scoring_mode ?? "amrap");

      if (scoringMode === "for_time") {
        const elapsed = effectiveSectionElapsedMs(segment, state);
        return elapsed > 0
          ? {
              section_id: segment.section_id,
              value: formatDurationMs(elapsed),
              score_type: "accumulated_work_time",
              kind: "final",
              source: "auto",
            }
          : null;
      }

      if (scoringMode === "for_quality") {
        return {
          section_id: segment.section_id,
          value: "Pass",
          score_type: "pass_fail",
          kind: "final",
          source: "auto",
        };
      }

      // amrap and to_failure require cross-window aggregation — backend handles it
      return null;
    }

    case "for_time":
```

- [x] **Step 2: TypeScript compile check**

```bash
cd apps/web && npx tsc --noEmit
```

Expected: no errors. The `score_type` values `"accumulated_work_time"` and `"pass_fail"` must already be in the `ScoreType` union from Task 4.

- [x] **Step 3: Commit**

```bash
git add apps/web/src/components/workouts/execution/progress.ts
git commit -m "feat(execution): add EMOM for_time and for_quality cases to computeMeasuredScore"
```

---

## Self-Review

### Spec Coverage

| Requirement | Covered by |
|---|---|
| Simple EMOM "For Time" — accumulated work time, lower is better | Task 1 (validation), Task 3 (snapshotter), Task 5 (store), Task 6 (UI), Task 8 (frontend pre-fill) |
| Simple EMOM "For Quality" — Binary Pass/Fail | Task 1, Task 3, Task 5, Task 6, Task 7, Task 8 |
| Simple EMOM "AMRAP" — total cumulative reps | Task 1, Task 3 (explicit amrap dispatch), Task 5, Task 6 |
| Simple EMOM "To Failure" — windows survived, open-ended | Task 1, Task 2 (max_windows segments), Task 3, Task 5, Task 6 |
| Complex EMOM "For Time" — same as simple EMOM but per-station tracking | Task 3 (same code path for complex_emom "for_time"), Task 8 |
| Complex EMOM "For Quality" — all stations pass/fail | Task 3 (same code path), Task 8 |
| Complex EMOM "AMRAP" — grand total OR lowest window | Task 1 (amrap_scoring_style), Task 3 (lowest_window branch), Task 5, Task 6 |
| Complex EMOM "To Failure" — total stations cleared | Task 1, Task 2, Task 3 (same "to_failure" path) |

### Placeholder Scan

No "TBD", "TODO", or incomplete steps found.

### Type Consistency

- `EmomScoringMode` defined in Task 4, used in Tasks 5, 6
- `EMOM_SCORING_MODE_SCORE_TYPE` defined in Task 4, used in Task 5 (`setEmomScoringMode` auto-sets `scoreType`)
- `EMOM_SCORING_MODE_LABELS` and `EMOM_SCORING_MODE_DESCRIPTIONS` defined in Task 4, used in Task 6
- `setEmomScoringMode` / `setEmomAmrapScoringStyle` added in Task 5, used in Task 6
- `"pass_fail"` ScoreType defined in Task 4, used in Task 3 (backend) and Task 7 (UI)
- `"accumulated_work_time"` ScoreType defined in Task 4, used in Task 3
- `"intervals_survived"` ScoreType defined in Task 4, used in Task 3
- `max_windows` in `FORMAT_FIELD_DEFS` (Task 4) → `formatParams` → `timer_config` serialization (Task 5) → `TimerSequenceBuilder` (Task 2)

All consistent. ✓
