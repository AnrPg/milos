defmodule MilosTraining.Execution.Queries.GetTrainingLogEntries do
  @moduledoc "Read side of standalone training-log entries (ADR-100)."

  alias MilosTraining.Execution.Domain.TrainingLogPolicy
  alias MilosTraining.Execution.TrainingLogStore

  def by_id_for_user(id, user_id) do
    case TrainingLogStore.get_entry(id) do
      %{user_id: ^user_id} = entry -> entry
      _missing_or_foreign -> nil
    end
  end

  def for_user(user_id, opts \\ []), do: TrainingLogStore.list_entries_for_user(user_id, opts)

  def live_source_reference_ids(user_id, source_type),
    do: TrainingLogStore.list_live_source_reference_ids(user_id, source_type)

  @doc """
  Completion records (execution-shaped) for every live entry of the user,
  across tenants - gamification stats are personal, mirroring how
  executions are counted. Requires an owner session (`app.user_id`).
  """
  def completion_records_for_user(user_id) do
    user_id
    |> TrainingLogStore.list_entries_for_user(include_voided: false, across_tenants: true)
    |> TrainingLogPolicy.completion_records()
  end
end
