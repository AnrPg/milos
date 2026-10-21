defmodule MilosTraining.Application.GoalFeedbackEntry do
  @moduledoc """
  Resolves the journal entry a «τι ένιωσες» request is about (ADR-163) and
  shapes the response both feedback use cases return.

  The entry must be the acting member's own execution or training-log
  entry; anyone else's (or a missing one) is `:not_found`. The goals shown
  are the member-visible goals of the entry's workout (its own or inherited,
  see `GetMemberWorkoutGoals`), read in the
  request's gym: an entry done in another gym, or without a workout, has
  none.
  """

  alias MilosTraining.Application.WorkoutGoalsPresenter, as: Presenter
  alias MilosTraining.{Journal, Workouts}

  def fetch(%{user_id: user_id} = context, entry_kind, entry_id) do
    with {:ok, entry_kind} <- entry_kind(entry_kind),
         {:ok, entry_id} <- cast_id(entry_id),
         %{user_id: ^user_id} = entry <-
           Journal.goal_feedback_entry(context, entry_kind, entry_id) do
      {:ok, Map.merge(entry, %{entry_kind: entry_kind, entry_id: entry_id})}
    else
      {:error, reason} -> {:error, reason}
      _missing_or_not_owner -> {:error, :not_found}
    end
  end

  def fetch(_context, _entry_kind, _entry_id), do: {:error, :not_found}

  def response(context, entry, feedback) do
    %{
      entry_kind: entry.entry_kind,
      entry_id: entry.entry_id,
      voided: entry.voided,
      goals: goals(context, entry),
      feedback: feedback && Map.take(feedback, [:felt_muscles, :felt_qualities, :updated_at])
    }
  end

  defp goals(%{organization_id: organization_id} = context, %{
         organization_id: organization_id,
         master_workout_id: workout_id
       })
       when is_binary(workout_id) do
    Presenter.member_goals(workout_id, Workouts.resolve_workout_goals(context, workout_id))
  end

  defp goals(_context, _entry), do: nil

  defp entry_kind(kind) do
    if kind in Journal.goal_feedback_entry_kinds(),
      do: {:ok, kind},
      else: {:error, :bad_request}
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
