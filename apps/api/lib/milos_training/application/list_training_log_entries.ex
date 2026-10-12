defmodule MilosTraining.Application.ListTrainingLogEntries do
  @moduledoc "Lists the acting user's training-log entries in the tenant (ADR-100)."

  alias MilosTraining.Execution

  @default_limit 100

  def call(%{organization_id: _} = context, %{id: user_id}) do
    Execution.with_training_log_context(context, fn ->
      {:ok, Execution.list_training_log_entries_for_user(user_id, limit: @default_limit)}
    end)
  end

  def call(_context, _actor), do: {:error, :organization_context_required}

  def get(%{organization_id: _} = context, %{id: user_id}, entry_id) do
    Execution.with_training_log_context(context, fn ->
      case Execution.get_training_log_entry_for_user(entry_id, user_id) do
        nil -> {:error, :not_found}
        entry -> {:ok, entry}
      end
    end)
  end

  def get(_context, _actor, _entry_id), do: {:error, :organization_context_required}
end
