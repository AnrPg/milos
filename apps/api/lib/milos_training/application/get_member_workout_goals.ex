defmodule MilosTraining.Application.GetMemberWorkoutGoals do
  @moduledoc """
  A member's read of a published workout's WOD goals (ADR-163). Only goals
  the coach saved and switched visible are returned; otherwise `goals` is
  nil, so a hidden goal set and an absent one look the same to a member.
  The workout must be a published workout of the member's gym (the same
  rule as reading the workout), else `:not_found`. Never the unsaved
  suggestion: the coach always has the chance to edit first.
  """

  alias MilosTraining.Application.WorkoutGoalsPresenter, as: Presenter
  alias MilosTraining.Workouts

  def call(context, workout_id) do
    with {:ok, workout_id} <- Ecto.UUID.cast(workout_id),
         %{} <- Workouts.get_workout(context, workout_id) do
      saved = Workouts.get_workout_goals(context, workout_id)
      {:ok, %{workout_id: workout_id, goals: saved && Presenter.member_goals(saved)}}
    else
      _missing -> {:error, :not_found}
    end
  end
end
