defmodule MilosTraining.Infrastructure.Journal.EctoGoalFeedbackStore do
  @moduledoc """
  Ecto adapter for «τι ένιωσες» goal feedback (ADR-163). Reads and writes
  in the caller's session; `goal_feedback_owner_policy` admits only the
  member's own rows and only on entries they own.
  """

  @behaviour MilosTraining.Journal.Ports.GoalFeedbackStore

  import Ecto.Query

  alias MilosTraining.Journal.GoalFeedback
  alias MilosTraining.Repo

  @impl true
  def feedback_entry(entry_kind, entry_id) do
    with {:ok, uuid} <- Ecto.UUID.dump(entry_id),
         %{rows: [[user_id, organization_id, workout_id, voided]]} <-
           Repo.query!(
             "SELECT user_id, organization_id, master_workout_id, voided " <>
               "FROM milos_goal_feedback_entry($1, $2)",
             [entry_kind, uuid]
           ) do
      %{
        user_id: load_uuid(user_id),
        organization_id: load_uuid(organization_id),
        master_workout_id: load_uuid(workout_id),
        voided: voided == true
      }
    else
      _missing -> nil
    end
  end

  @impl true
  def get_feedback(entry_kind, entry_id, user_id) do
    case Repo.one(by_entry(entry_kind, entry_id, user_id)) do
      nil -> nil
      feedback -> normalize(feedback)
    end
  end

  @impl true
  def list_by_entries(_entry_kind, [], _user_id), do: []

  def list_by_entries(entry_kind, entry_ids, user_id) do
    GoalFeedback
    |> where([feedback], feedback.entry_kind == ^entry_kind and feedback.entry_id in ^entry_ids)
    |> where([feedback], feedback.user_id == ^user_id)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def put_feedback(attrs) do
    existing = Repo.one(by_entry(attrs.entry_kind, attrs.entry_id, attrs.user_id))

    (existing || %GoalFeedback{})
    |> GoalFeedback.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, feedback} -> {:ok, normalize(feedback)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def list_feedback_for({kind, id}) when kind in [:workout, :scheduled_class] do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        GoalFeedback
        |> join(
          :inner_lateral,
          [feedback],
          entry in fragment(
            "SELECT master_workout_id, scheduled_class_id, voided FROM milos_goal_feedback_entry_scope(?, ?)",
            feedback.entry_kind,
            feedback.entry_id
          ),
          on: true
        )
        |> where([_feedback, entry], entry.voided == false)
        |> scope_to(kind, id)
        |> select([feedback], %{
          felt_muscles: feedback.felt_muscles,
          felt_qualities: feedback.felt_qualities
        })
        |> Repo.all()

      :error ->
        []
    end
  end

  defp scope_to(query, :workout, id),
    do: where(query, [_feedback, entry], entry.master_workout_id == type(^id, Ecto.UUID))

  defp scope_to(query, :scheduled_class, id),
    do: where(query, [_feedback, entry], entry.scheduled_class_id == type(^id, Ecto.UUID))

  defp by_entry(entry_kind, entry_id, user_id) do
    GoalFeedback
    |> where([feedback], feedback.entry_kind == ^entry_kind and feedback.entry_id == ^entry_id)
    |> where([feedback], feedback.user_id == ^user_id)
  end

  defp normalize(%GoalFeedback{} = feedback) do
    %{
      entry_kind: feedback.entry_kind,
      entry_id: feedback.entry_id,
      felt_muscles: feedback.felt_muscles || [],
      felt_qualities: feedback.felt_qualities || [],
      updated_at: feedback.updated_at
    }
  end

  defp load_uuid(nil), do: nil
  defp load_uuid(binary), do: Ecto.UUID.load!(binary)
end
