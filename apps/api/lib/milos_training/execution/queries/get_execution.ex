defmodule MilosTraining.Execution.Queries.GetExecution do
  alias MilosTraining.Execution.ExecutionStore

  def by_id(id), do: ExecutionStore.get_execution(id)

  def by_id_for_user(id, user_id) do
    case ExecutionStore.get_execution(id) do
      %{user_id: ^user_id} = execution -> execution
      _other -> nil
    end
  end

  def for_user(user_id), do: ExecutionStore.list_executions_for_user(user_id)
end
