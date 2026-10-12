defmodule MilosTraining.Application.AcknowledgeAthleteInjuryWarnings do
  @moduledoc """
  Staff use case (ADR-114): a coach acknowledged the injury warnings shown
  for athletes on a workout. The warnings are re-evaluated server-side (the
  client never supplies levels or counts) and `injury_warning_acknowledged`
  is recorded per warned athlete. Acknowledging never changes the
  assignment, booking or workout.
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
      warned = Enum.reject(result.athletes, &(&1.level == :none))

      Enum.each(warned, fn athlete ->
        InjuryWarningEvaluation.track(
          "injury_warning_acknowledged",
          context,
          "staff",
          result.workout_id,
          athlete,
          athlete_id: athlete.user_id,
          surface: surface,
          source_context_id: source_context_id
        )
      end)

      {:ok, %{acknowledged_count: length(warned)}}
    end
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
