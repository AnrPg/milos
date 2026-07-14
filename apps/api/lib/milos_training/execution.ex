defmodule MilosTraining.Execution do
  alias MilosTraining.Execution.Commands.{
    CompleteExecution,
    StartExecution,
    SubmitExecutionNote,
    UpdateExecutionProgress
  }

  alias MilosTraining.Execution.Domain.TimerSequenceBuilder
  alias MilosTraining.Execution.Queries.GetExecution

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
  defdelegate build_timer_sequence(workout), to: TimerSequenceBuilder, as: :build
end
