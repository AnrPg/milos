defmodule MilosTraining.Application.StartWorkoutExecution do
  alias MilosTraining.Application.{
    AuthorizeFinanceEntitlement,
    AuthorizeWorkoutExecutionSource
  }

  alias MilosTraining.Execution
  alias MilosTraining.Execution.ExecutionStore

  def call(context, actor, params),
    do: ExecutionStore.with_user_context(context, fn -> run(context, actor, params) end)

  def call(actor, params) do
    run(nil, actor, params)
  end

  defp run(context, actor, params) do
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
         :ok <- authorize_entitlement(context, actor, authorized_source) do
      Execution.start_execution(actor.id, Map.merge(params, authorized_source))
    end
  end

  defp authorize_entitlement(context, actor, authorized_source) do
    request = AuthorizeFinanceEntitlement.execution_request(authorized_source)

    result =
      case context do
        nil -> AuthorizeFinanceEntitlement.call(actor, request)
        context -> AuthorizeFinanceEntitlement.call(context, actor, request)
      end

    case result do
      {:ok, _decision} -> :ok
      result -> result
    end
  end
end
