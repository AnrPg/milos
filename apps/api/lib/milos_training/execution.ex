defmodule MilosTraining.Execution do
  alias MilosTraining.Execution.Commands.{
    CompleteExecution,
    StartExecution,
    SubmitExecutionNote,
    UpdateExecutionProgress
  }

  alias MilosTraining.Execution.Domain.{ExecutionKpis, TimerSequenceBuilder}
  alias MilosTraining.Execution.Queries.GetExecution
  alias MilosTraining.Execution.ExecutionStore

  defdelegate start_execution(user_id, params), to: StartExecution, as: :call
  defdelegate complete_execution(id, user_id, params), to: CompleteExecution, as: :call
  defdelegate complete_execution(id, user_id, params, opts), to: CompleteExecution, as: :call

  defdelegate update_execution_progress(id, user_id, params),
    to: UpdateExecutionProgress,
    as: :call

  defdelegate submit_execution_note(id, user_id, params), to: SubmitExecutionNote, as: :call
  defdelegate get_execution(id), to: GetExecution, as: :by_id
  defdelegate get_execution_for_user(id, user_id), to: GetExecution, as: :by_id_for_user
  defdelegate list_executions_for_user(user_id), to: GetExecution, as: :for_user

  def list_executions_for_coaching(user_id),
    do: ExecutionStore.list_executions_for_coaching(user_id)

  @doc "Execution KPI report for the current organization since `since`."
  def execution_kpis(%DateTime{} = since) do
    since
    |> ExecutionStore.list_executions_for_kpis()
    |> ExecutionKpis.summarize()
    |> Map.put(:since, since)
  end

  defdelegate build_timer_sequence(workout), to: TimerSequenceBuilder, as: :build
  defdelegate preview_timer_sequence(workout), to: TimerSequenceBuilder, as: :preview
end
