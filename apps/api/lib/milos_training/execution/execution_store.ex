defmodule MilosTraining.Execution.ExecutionStore do
  @behaviour MilosTraining.Execution.Ports.ExecutionStore

  defp adapter do
    Application.fetch_env!(:milos_training, :execution_store)
  end

  @impl true
  def start_execution(params), do: adapter().start_execution(params)

  @impl true
  def complete_execution(id, params), do: adapter().complete_execution(id, params)

  @impl true
  def complete_execution_with_job(id, params, job_changeset),
    do: adapter().complete_execution_with_job(id, params, job_changeset)

  @impl true
  def update_execution(id, params), do: adapter().update_execution(id, params)

  @impl true
  def get_execution(id), do: adapter().get_execution(id)

  @impl true
  def list_executions_for_user(user_id), do: adapter().list_executions_for_user(user_id)

  @impl true
  def progress_operation_applied?(execution_id, user_id, operation_id),
    do: adapter().progress_operation_applied?(execution_id, user_id, operation_id)
end
