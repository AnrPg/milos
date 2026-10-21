defmodule MilosTraining.Application.SaveWorkoutGoals do
  @moduledoc """
  Staff save of a workout's WOD goals (ADR-163). The goals are validated
  against the taxonomy (`GoalSet`), stamped with the taxonomy version and
  the acting staff member, and marked `suggested` when they are exactly the
  live suggestion (muscles and qualities), otherwise `edited`.

  `visible_to_members` is the editor's toggle; when the request leaves it
  out, the saved value is kept (hidden for a first save).
  """

  alias MilosTraining.Anatomy
  alias MilosTraining.Application.WorkoutGoalsPresenter, as: Presenter
  alias MilosTraining.Workouts

  def call(context, workout_id, params) when is_map(params) do
    with {:ok, workout_id} <- cast_id(workout_id),
         {:ok, workout} <- fetch_workout(context, workout_id),
         {:ok, goals} <- Anatomy.normalize_goals(params),
         {:ok, visible} <- visibility(params) do
      suggestion = Presenter.suggestion(workout)
      current = Workouts.get_workout_goals(context, workout_id)
      muscles = Enum.map(goals.muscles, &Presenter.muscle/1)

      attrs = %{
        muscles: muscles,
        qualities: goals.qualities,
        stimulus: goals.stimulus,
        visible_to_members: visible_value(visible, current),
        source: source(muscles, goals.qualities, suggestion),
        taxonomy_version: Anatomy.taxonomy_version(),
        updated_by_id: context.user_id
      }

      with {:ok, saved} <- Workouts.put_workout_goals(context, workout_id, attrs) do
        {:ok,
         %{
           goals: Presenter.staff_goals(workout_id, saved, suggestion),
           suggestion: suggestion
         }}
      end
    end
  end

  def call(_context, _workout_id, _params), do: {:error, :bad_request}

  defp fetch_workout(context, workout_id) do
    case Workouts.get_workout_for_admin(context, workout_id) do
      %{} = workout -> {:ok, workout}
      _missing -> {:error, :not_found}
    end
  end

  defp visibility(params) do
    case Map.get(params, "visible_to_members", Map.get(params, :visible_to_members)) do
      nil -> {:ok, :keep}
      value when is_boolean(value) -> {:ok, value}
      _other -> {:error, {:invalid_goals, %{visible_to_members: "must be true or false"}}}
    end
  end

  defp visible_value(:keep, nil), do: false
  defp visible_value(:keep, current), do: current.visible_to_members
  defp visible_value(value, _current), do: value

  defp source(muscles, qualities, suggestion) do
    if Enum.sort(muscles) == Enum.sort(suggestion.muscles) and
         Enum.sort(qualities) == Enum.sort(suggestion.qualities),
       do: "suggested",
       else: "edited"
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
