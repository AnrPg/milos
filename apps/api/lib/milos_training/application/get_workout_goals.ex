defmodule MilosTraining.Application.GetWorkoutGoals do
  @moduledoc """
  Staff read of a workout's WOD goals (ADR-163): the saved goals, or the
  live suggestion (`source: "suggested"`, `saved: false`) when none are
  saved, plus the suggestion itself so the editor can offer «reset to
  suggestion». Drafts are read too, so goals can be set before publishing.
  """

  alias MilosTraining.Application.WorkoutGoalsPresenter, as: Presenter
  alias MilosTraining.Workouts

  def call(context, workout_id) do
    with {:ok, workout_id} <- cast_id(workout_id),
         %{} = workout <- Workouts.get_workout_for_admin(context, workout_id) do
      suggestion = Presenter.suggestion(workout)
      saved = Workouts.get_workout_goals(context, workout_id)

      {:ok,
       %{
         goals: Presenter.staff_goals(workout_id, saved, suggestion),
         suggestion: suggestion
       }}
    else
      _missing -> {:error, :not_found}
    end
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
