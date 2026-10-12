defmodule MilosTraining.Application.GetMyWorkoutInjuryWarnings do
  @moduledoc """
  Athlete/member use case (ADR-124): the acting user's own injury warnings
  for a workout they are about to start - including personal self-reported
  injuries, which they own. `injury_warning_shown` is recorded only from
  this organization's injuries, so a personal injury never becomes a
  tenant analytics fact.
  """

  alias MilosTraining.Application.InjuryWarningEvaluation

  def call(context, workout_id, params \\ %{}) do
    surface =
      params
      |> param(:surface)
      |> InjuryWarningEvaluation.surface(InjuryWarningEvaluation.self_surfaces())

    with {:ok, result, tenant_evaluation} <- InjuryWarningEvaluation.for_self(context, workout_id) do
      InjuryWarningEvaluation.track(
        "injury_warning_shown",
        context,
        "self",
        result.workout_id,
        tenant_evaluation,
        surface: surface,
        source_context_id:
          InjuryWarningEvaluation.source_context_id(param(params, :source_context_id))
      )

      {:ok, result}
    end
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
