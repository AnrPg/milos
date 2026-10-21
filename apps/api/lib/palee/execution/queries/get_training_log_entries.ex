defmodule Palee.Execution.Queries.GetTrainingLogEntries do
  @moduledoc "Read side of standalone training-log entries (ADR-118)."

  alias Palee.Execution.Domain.TrainingLogPolicy
  alias Palee.Execution.TrainingLogStore

  def by_id_for_user(id, user_id) do
    case TrainingLogStore.get_entry(id) do
      %{user_id: ^user_id} = entry -> entry
      _missing_or_foreign -> nil
    end
  end

  @doc """
  ADR-120: looks up a prior submission of the request's `idempotency_key`.
  Returns `:none` when there is none (or the key is unusable; the command
  validates it), `{:ok, entry}` for a matching replay, or
  `{:error, :idempotency_key_conflict}` when the key names another source.
  """
  def replay_for_request(user_id, params) when is_map(params) do
    with key when is_binary(key) <- params["idempotency_key"] || params[:idempotency_key],
         %{} = entry <- TrainingLogStore.get_entry_by_idempotency_key(user_id, key) do
      case TrainingLogPolicy.replay_decision(entry, params) do
        :replay -> {:ok, entry}
        {:error, reason} -> {:error, reason}
      end
    else
      _none -> :none
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
