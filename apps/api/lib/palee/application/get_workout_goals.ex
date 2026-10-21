defmodule Palee.Application.GetWorkoutGoals do
  @moduledoc """
  Staff read of a workout's WOD goals (ADR-163): its own saved goals; else
  the goals it inherits from the workout it was copied from (a class
  variant or member version, `inherited_from` set); else the live
  suggestion (`source: "suggested"`, `saved: false`) with the toggle at the
  gym's `wod_goals_visible_by_default`. The suggestion itself is always
  returned so the editor can offer «reset to suggestion». Drafts are read
  too, so goals can be set before publishing.
  """

  alias Palee.Application.WorkoutGoalsPresenter, as: Presenter
  alias Palee.{Organizations, Workouts}

  def call(context, workout_id) do
    with {:ok, workout_id} <- cast_id(workout_id),
         %{} = workout <- Workouts.get_workout_for_admin(context, workout_id) do
      suggestion = Presenter.suggestion(workout)
      resolved = Workouts.resolve_workout_goals(context, workout_id)
      default_visible = default_visible(context, resolved)

      {:ok,
       %{
         goals: Presenter.staff_goals(workout_id, resolved, suggestion, default_visible),
         suggestion: suggestion
       }}
    else
      _missing -> {:error, :not_found}
    end
  end

  @doc "The gym's starting value of the members toggle, read only when needed."
  def default_visible(context, %{goals: nil}),
    do: Organizations.get_workout_settings(context).wod_goals_visible_by_default

  def default_visible(_context, _resolved), do: false

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
