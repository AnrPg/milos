defmodule Palee.Execution.Domain.PlanTimer do
  @moduledoc """
  ADR-270: the timer segments of a structured plan workout, one per plan
  section, from the section's canonical clock
  (`Palee.Workouts.Domain.StructuredPlan.Prescription`).

  The web runner executes a plan section itself (`sections[].plan`), so these
  segments are the server's view of it: keyed `plan:<section id>` like the
  web's `scoreSegment`, carrying the section's score (so completion accepts
  the athlete's score and writes it as the section score) and the clock as a
  timer (so the class timer and cast screens can run it). Format
  `structured_plan` keeps the score type the section's own.
  """

  alias Palee.Workouts.Domain.StructuredPlan
  alias Palee.Workouts.Domain.StructuredPlan.Prescription

  @doc "The segments of a workout's plan sections, in order; sections without a plan are skipped."
  def build(sections) when is_list(sections) do
    sections
    |> Enum.sort_by(&(value(&1, :order) || 0))
    |> Enum.flat_map(fn section ->
      plan = value(section, :plan)

      case Prescription.build(plan) do
        %{clock: clock} -> [segment(section, plan, clock)]
        nil -> []
      end
    end)
  end

  def build(_sections), do: []

  @doc "The score config of a plan, as the web runner's segment carries it; nil when not scored."
  def score_config(plan, label) do
    case StructuredPlan.score_config(plan) do
      nil ->
        nil

      config ->
        %{type: config["type"], label: label}
        |> then(&if(config["unit"], do: Map.put(&1, :unit, config["unit"]), else: &1))
    end
  end

  defp segment(section, plan, clock) do
    id = to_string(value(section, :id))
    name = value(section, :name) || ""
    score = score_config(plan, name)

    Map.merge(
      %{
        segment_key: "plan:#{id}",
        section_id: id,
        section_name: name,
        format: "structured_plan",
        phase: if(clock.flow == "rest", do: "rest", else: "work"),
        round: nil,
        label: name,
        label_key: nil,
        label_params: %{},
        scoreable: score != nil,
        score_config: score,
        exercises: []
      },
      timing(clock)
    )
  end

  defp timing(%{flow: "for_time"} = clock),
    do: timer(:countup, clock.cap_secs, nil, clock)

  defp timing(%{flow: "amrap"} = clock) do
    windows = clock.windows_secs || []
    rest = (clock.rest_secs && clock.rest_secs.min) || 0
    total = Enum.sum(windows) + rest * max(length(windows) - 1, 0)
    timer(:countdown, positive(total), nil, clock, windows_pattern(windows, rest))
  end

  defp timing(%{flow: "emom"} = clock),
    do: timer(:interval_cycle, clock.every_secs, clock.times, clock)

  defp timing(%{flow: "intervals", work_secs: work} = clock) when is_integer(work) do
    pattern = Enum.filter([work, clock.off_secs], &positive/1)
    windows = clock.rounds && clock.rounds * length(pattern)
    timer(:interval_cycle, work, windows, clock, %{interval_pattern_seconds: pattern})
  end

  defp timing(%{flow: "rest"} = clock), do: timer(:countdown, clock.dur_secs, nil, clock)
  defp timing(clock), do: timer(:countup, nil, nil, clock)

  defp timer(kind, duration, total_rounds, clock, config \\ %{}) do
    %{
      kind: kind,
      duration_seconds: positive(duration),
      total_rounds: positive(total_rounds),
      timer_config:
        Map.merge(config, %{
          plan_flow: clock.flow,
          open_ended: clock.open_ended,
          interrupt_every_seconds: clock.interrupt_every_secs
        })
    }
  end

  defp windows_pattern([_one], _rest), do: %{}
  defp windows_pattern([], _rest), do: %{}

  defp windows_pattern(windows, rest),
    do: %{amrap_windows_seconds: windows, rest_between_seconds: rest}

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: nil

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
