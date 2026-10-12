defmodule MilosTraining.Application.EvaluateAthleteInjuryWarnings do
  @moduledoc """
  Staff use case (ADR-114): injury safety warnings for a set of athletes or
  members against one workout - the assign-workout dialog, the class roster
  and the member dossier. Only organization-provenance injuries are visible
  (see `InjuryWarningEvaluation`). Records `injury_warning_shown` once per
  warned athlete, surface and day. Non-blocking by design.
  """

  alias MilosTraining.Application.InjuryWarningEvaluation

  def call(context, params) do
    surface =
      params
      |> param(:surface)
      |> InjuryWarningEvaluation.surface(InjuryWarningEvaluation.staff_surfaces())

    source_context_id =
      InjuryWarningEvaluation.source_context_id(param(params, :source_context_id))

    with {:ok, result} <-
           InjuryWarningEvaluation.for_athletes(
             context,
             param(params, :workout_id),
             param(params, :user_ids)
           ) do
      Enum.each(result.athletes, fn athlete ->
        InjuryWarningEvaluation.track(
          "injury_warning_shown",
          context,
          "staff",
          result.workout_id,
          athlete,
          athlete_id: athlete.user_id,
          surface: surface,
          source_context_id: source_context_id
        )
      end)

      {:ok, result}
    end
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
