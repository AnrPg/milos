defmodule MilosTraining.Application.PublishWorkoutDsl do
  @moduledoc """
  Authoritatively parses, preflights, and publishes a revisioned Quick Text draft.
  """

  alias MilosTraining.Application.PublishWorkout
  alias MilosTraining.{Execution, Workouts}

  def call(id, params) do
    source = value(params, :source)
    acknowledge_warnings? = value(params, :acknowledge_warnings, false) == true

    with {:ok, parsed} <- Workouts.parse_dsl(source),
         :ok <- require_warning_acknowledgement(parsed.diagnostics, acknowledge_warnings?),
         :ok <- preflight(parsed.workout),
         {:ok, execution_preview} <- build_execution_preview(parsed.workout),
         publish_params <- publish_params(parsed, params),
         {:ok, workout} <- PublishWorkout.call(id, publish_params) do
      {:ok,
       %{
         workout: workout,
         formatted_source: Workouts.format_dsl(parsed.workout, version: parsed.version),
         diagnostics: parsed.diagnostics,
         execution_preview: execution_preview
       }}
    end
  end

  defp require_warning_acknowledgement(diagnostics, false) do
    warnings = Enum.filter(diagnostics, &(&1.severity == :warning))
    if warnings == [], do: :ok, else: {:error, {:dsl_warnings_require_acknowledgement, warnings}}
  end

  defp require_warning_acknowledgement(_diagnostics, _acknowledged), do: :ok

  defp preflight(workout) do
    active_slugs = Workouts.list_scale_levels() |> Enum.map(& &1.slug)
    Workouts.preflight_dsl(workout, active_slugs)
  end

  defp build_execution_preview(workout) do
    segments = Execution.build_timer_sequence(workout)

    invalid_segment =
      Enum.find(segments, fn segment ->
        segment.kind == :countdown and
          (not is_integer(segment.duration_seconds) or segment.duration_seconds <= 0)
      end)

    cond do
      segments == [] -> {:error, :empty_execution_sequence}
      invalid_segment -> {:error, :invalid_execution_timer_segment}
      true -> {:ok, summarize_segments(segments)}
    end
  end

  defp summarize_segments(segments) do
    %{
      segment_count: length(segments),
      timed_seconds:
        segments
        |> Enum.map(&(&1.duration_seconds || 0))
        |> Enum.sum(),
      formats: segments |> Enum.map(& &1.format) |> Enum.uniq()
    }
  end

  defp publish_params(parsed, params) do
    parsed.workout
    |> Map.put(:authoring_mode, "quick_text")
    |> Map.put(:dsl_version, parsed.version)
    |> Map.put(:dsl_source, value(params, :source))
    |> Map.put(:dsl_document, value(params, :document))
    |> Map.put(:last_dsl_diagnostics, Enum.map(parsed.diagnostics, &persisted_diagnostic/1))
    |> Map.put(:expected_source_revision, value(params, :expected_source_revision))
  end

  defp persisted_diagnostic(diagnostic) do
    %{
      "code" => to_string(diagnostic.code),
      "severity" => to_string(diagnostic.severity),
      "line" => diagnostic.line,
      "column" => diagnostic.column,
      "params" => Map.new(diagnostic.params, fn {key, value} -> {to_string(key), value} end)
    }
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
