defmodule MilosTraining.Application.StartWorkoutExecution do
  alias MilosTraining.Application.{
    AuthorizeFinanceEntitlement,
    AuthorizeWorkoutExecutionSource
  }

  alias MilosTraining.Execution
  alias MilosTraining.Execution.ExecutionStore
  alias MilosTraining.Organizations

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

    with {:ok, finance_context} <- finance_context(context, authorized_source) do
      case AuthorizeFinanceEntitlement.call(finance_context, actor, request) do
        {:ok, _decision} -> :ok
        result -> result
      end
    end
  end

  defp finance_context(%{organization_id: organization_id} = context, %{
         organization_id: organization_id
       }) do
    {:ok, context}
  end

  defp finance_context(%{organization_id: _context_org}, %{organization_id: _source_org}),
    do: {:error, :organization_context_mismatch}

  defp finance_context(_context, %{organization_id: organization_id})
       when is_binary(organization_id) do
    Organizations.resolve_system_tenant_context(organization_id, :execution_authorization, %{
      service: __MODULE__
    })
  end

  defp finance_context(_context, _authorized_source), do: {:error, :organization_context_required}
end
