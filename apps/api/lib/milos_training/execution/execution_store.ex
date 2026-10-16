defmodule MilosTraining.Execution.ExecutionStore do
  @behaviour MilosTraining.Execution.Ports.ExecutionStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter do
    Application.fetch_env!(:milos_training, :execution_store)
  end

  def with_user_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  def with_authorization_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(Map.put(context, :execution_authorization_check, true), fun)

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
  def list_executions_for_coaching(user_id), do: adapter().list_executions_for_coaching(user_id)

  @impl true
  def list_executions_for_kpis(since), do: adapter().list_executions_for_kpis(since)

  @impl true
  def list_stale_executions(started_before, started_after, limit),
    do: adapter().list_stale_executions(started_before, started_after, limit)

  @impl true
  def last_progress_at(execution_id), do: adapter().last_progress_at(execution_id)

  @impl true
  def list_execution_items(user_id, bound, limit, scope),
    do: adapter().list_execution_items(user_id, bound, limit, scope)

  @impl true
  def set_execution_visibility(id, user_id, rung),
    do: adapter().set_execution_visibility(id, user_id, rung)

  @impl true
  def move_executions(user_id, from, to), do: adapter().move_executions(user_id, from, to)

  @impl true
  def progress_operation_applied?(execution_id, user_id, operation_id),
    do: adapter().progress_operation_applied?(execution_id, user_id, operation_id)
end
