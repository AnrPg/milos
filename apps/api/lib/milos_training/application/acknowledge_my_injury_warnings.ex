defmodule MilosTraining.Application.AcknowledgeMyInjuryWarnings do
  @moduledoc """
  Athlete/member use case (ADR-124): the user acknowledged their own injury
  warnings for a workout. Re-evaluated server-side; the analytics event only
  reflects this organization's injuries (see `GetMyWorkoutInjuryWarnings`).
  Acknowledging never blocks or alters the workout.
  """

  alias MilosTraining.Application.InjuryWarningEvaluation

  def call(context, workout_id, params \\ %{}) do
    surface =
      params
      |> param(:surface)
      |> InjuryWarningEvaluation.surface(InjuryWarningEvaluation.self_surfaces())

    with {:ok, result, tenant_evaluation} <- InjuryWarningEvaluation.for_self(context, workout_id) do
      InjuryWarningEvaluation.track(
        "injury_warning_acknowledged",
        context,
        "self",
        result.workout_id,
        tenant_evaluation,
        surface: surface,
        source_context_id:
          InjuryWarningEvaluation.source_context_id(param(params, :source_context_id))
      )

      {:ok, %{level: result.level, warning_count: length(result.warnings)}}
    end
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
