defmodule Palee.Workouts.Queries.PlanPrescriptions do
  @moduledoc """
  The port other contexts read structured plan workouts (ADR-270) through,
  so the executor, progress, analytics and the rest never parse a plan or
  reach into `StructuredPlan` themselves. Works on the workout read model
  (`Workouts.get_workout/2`: sections with their `plan`) and on the
  athlete's plan actuals (`Execution.list_plan_sets/1`).

  * `decorate/1` — the read model of a plan section carries the score its
    plan sets (`scoreable`, `score_config`), like any other section, so the
    training log, WOD leaderboards, PR detection and the timer sequence
    score it without knowing about plans;
  * `workload/3` — sets, reps, volume, calories, distance and the time
    domain of what an athlete did (`PlanWorkload`);
  * `exercise_weights/1` — how many sets each exercise of a plan section is
    done in, as prescribed.
  """

  alias Palee.Workouts.Domain.{PlanWorkload, StructuredPlanWorkout}

  @doc "Whether a workout (read model or params) is written in the structured WOD editor."
  @spec plan_workout?(term()) :: boolean()
  def plan_workout?(%{} = workout), do: StructuredPlanWorkout.plan?(workout)
  def plan_workout?(_workout), do: false

  @doc "Whether a section carries a plan."
  @spec plan_section?(term()) :: boolean()
  def plan_section?(%{} = section), do: is_map(field(section, :plan))
  def plan_section?(_section), do: false

  @doc """
  The workout with every plan section scored as its plan says
  (`scoreable`, `score_config` with string keys like a stored one). Other
  sections and workouts are returned as they are.
  """
  @spec decorate(term()) :: term()
  def decorate(%{sections: sections} = workout) when is_list(sections),
    do: %{workout | sections: Enum.map(sections, &decorate_section/1)}

  def decorate(workout), do: workout

  defp decorate_section(%{} = section) do
    if plan_section?(section) do
      case score_config(section) do
        nil -> section |> Map.put(:scoreable, false) |> Map.put(:score_config, nil)
        config -> section |> Map.put(:scoreable, true) |> Map.put(:score_config, config)
      end
    else
      section
    end
  end

  defp decorate_section(section), do: section

  @doc "The score config of a plan section (`%{\"type\", \"unit\"}`), nil when it is not scored."
  @spec score_config(map()) :: map() | nil
  def score_config(section) do
    case section |> field(:plan) |> plan_score() |> PlanWorkload.score_config() do
      nil -> nil
      config -> Map.new(config, fn {key, value} -> {Atom.to_string(key), value} end)
    end
  end

  defp plan_score(%{"score" => score}), do: score
  defp plan_score(_plan), do: nil

  @doc """
  What an athlete did in the plan sections of a workout, or nil when it has
  none. `plan_sets` are the athlete's actuals of one execution (any
  section). Options: `:section_scores` and `:section_elapsed_ms` of the
  execution (an open-ended section counts its scored rounds without
  actuals; interruptions fire in the time spent), `:one_rep_max`
  (`fn name, exercise_ref -> kg | nil end`).

  `%{sections: [%{section_id, name, flow, source, time_domain, exercises,
  totals}], totals, exercises}`; see `PlanWorkload`.
  """
  @spec workload(term(), [map()], keyword()) :: map() | nil
  def workload(workout, plan_sets \\ [], opts \\ [])

  def workload(%{sections: sections}, plan_sets, opts) when is_list(sections) do
    case Enum.filter(sections, &plan_section?/1) do
      [] ->
        nil

      plan_sections ->
        by_section = Enum.group_by(List.wrap(plan_sets), &to_string(field(&1, :section_id)))
        scores = score_lookup(Keyword.get(opts, :section_scores))
        elapsed = Keyword.get(opts, :section_elapsed_ms) || %{}

        workloads =
          plan_sections
          |> Enum.map(fn section ->
            id = to_string(field(section, :id))

            section_opts = [
              one_rep_max: Keyword.get(opts, :one_rep_max),
              rounds_done: rounds_done(section, Map.get(scores, id)),
              elapsed_secs: elapsed_secs(elapsed, id)
            ]

            case PlanWorkload.section(field(section, :plan), Map.get(by_section, id, []), section_opts) do
              nil -> nil
              workload -> Map.merge(%{section_id: id, name: field(section, :name)}, workload)
            end
          end)
          |> Enum.reject(&is_nil/1)

        workloads
        |> PlanWorkload.merge()
        |> Map.put(:sections, workloads)
    end
  end

  def workload(_workout, _plan_sets, _opts), do: nil

  @doc """
  The exercises of a workout's plan sections with how many sets each is done
  in, as prescribed: `%{name, exercise_ref, sets}` in plan order.
  """
  @spec exercise_weights(term()) :: [map()]
  def exercise_weights(%{sections: sections}) when is_list(sections) do
    sections
    |> Enum.filter(&plan_section?/1)
    |> Enum.flat_map(&PlanWorkload.exercise_weights(field(&1, :plan)))
  end

  def exercise_weights(_workout), do: []

  defp score_lookup(scores) when is_list(scores) do
    scores
    |> Enum.filter(&is_map/1)
    |> Map.new(&{to_string(field(&1, :section_id)), &1})
  end

  defp score_lookup(_scores), do: %{}

  # Rounds of an open-ended section, from a rounds + reps score.
  defp rounds_done(section, %{} = score) do
    config = score_config(section) || %{}

    if config["type"] == "rounds_reps",
      do: PlanWorkload.rounds_from_score(field(score, :value))
  end

  defp rounds_done(_section, _score), do: nil

  defp elapsed_secs(elapsed, id) when is_map(elapsed) do
    case Map.get(elapsed, id) do
      ms when is_integer(ms) and ms >= 0 -> div(ms, 1000)
      _unknown -> nil
    end
  end

  defp elapsed_secs(_elapsed, _id), do: nil

  defp field(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp field(_map, _key), do: nil
end
