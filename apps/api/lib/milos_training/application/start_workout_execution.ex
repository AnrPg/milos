defmodule MilosTraining.Application.StartWorkoutExecution do
  alias MilosTraining.Application.{
    AuthorizeFinanceEntitlement,
    AuthorizeWorkoutExecutionSource
  }

  alias MilosTraining.Execution

  def call(actor, params) do
    workout_id = params[:master_workout_id] || params["master_workout_id"]
    source = params[:source] || params["source"]
    source_reference_id = params[:source_reference_id] || params["source_reference_id"]

    with :ok <- AuthorizeFinanceEntitlement.call(actor.id, :workout_execution),
         {:ok, authorized_source} <-
           AuthorizeWorkoutExecutionSource.call(
             actor,
             workout_id,
             source,
             source_reference_id
           ) do
      Execution.start_execution(actor.id, Map.merge(params, authorized_source))
    end
  end
end
