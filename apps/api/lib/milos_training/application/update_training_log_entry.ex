defmodule MilosTraining.Application.UpdateTrainingLogEntry do
  @moduledoc """
  Owner edit of a training-log entry within the tenant (ADR-118).

  Edits change the performed details only; they do not re-run the completion
  projection (gamification is computed once, when the entry is logged).
  """

  alias MilosTraining.Application.JournalComments
  alias MilosTraining.{Execution, Workouts}

  def call(%{organization_id: _} = context, %{id: user_id}, entry_id, params)
      when is_map(params) do
    Execution.with_training_log_context(context, fn ->
      case Execution.get_training_log_entry_for_user(entry_id, user_id) do
        nil ->
          {:error, :not_found}

        entry ->
          with {:ok, updated} <-
                 Execution.update_training_log_entry(entry_id, user_id, params,
                   now: DateTime.utc_now(),
                   allowed_section_ids: allowed_section_ids(context, entry)
                 ),
               do: {:ok, JournalComments.attach(updated, "training_log")}
      end
    end)
  end

  def call(_context, _actor, _entry_id, _params), do: {:error, :organization_context_required}

  defp allowed_section_ids(_context, %{master_workout_id: nil}), do: []

  defp allowed_section_ids(context, %{master_workout_id: workout_id}) do
    context
    |> Workouts.get_workout(workout_id)
    |> Execution.training_log_scoreable_sections()
    |> Enum.map(& &1.id)
  end
end
