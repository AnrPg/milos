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

    with {:ok, authorized_source} <-
           AuthorizeWorkoutExecutionSource.call(
             actor,
             workout_id,
             source,
             source_reference_id
           ),
         :ok <- authorize_entitlement(actor, authorized_source) do
      Execution.start_execution(actor.id, Map.merge(params, authorized_source))
    end
  end

  defp authorize_entitlement(actor, authorized_source) do
    request = AuthorizeFinanceEntitlement.execution_request(authorized_source)

    case AuthorizeFinanceEntitlement.call(actor, request) do
      {:ok, _decision} -> :ok
      result -> result
    end
  end
end
