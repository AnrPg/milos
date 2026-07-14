defmodule MilosTraining.Application.AddExecutionModifications do
  alias MilosTraining.Execution
  alias MilosTraining.Execution.ExecutionStore, as: ExStore

  def call(execution_id, user_id, modifications) do
    case Execution.get_execution_for_user(execution_id, user_id) do
      nil ->
        {:error, :not_found}

      execution ->
        existing = execution.exercise_modifications || []
        logged_at = DateTime.to_iso8601(DateTime.utc_now())
        timestamped = Enum.map(modifications, &Map.put(&1, "logged_at", logged_at))
        merged = existing ++ timestamped
        ExStore.update_execution(execution_id, %{exercise_modifications: merged})
    end
  end
end
