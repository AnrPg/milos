defmodule MilosTraining.Application.GetWorkoutTimerSequence do
  alias MilosTraining.Application.{AuthorizeFinanceEntitlement, AuthorizeWorkoutExecutionSource}
  alias MilosTraining.{Execution, Organizations, Workouts}
  alias MilosTraining.Execution.ExecutionStore

  def call(context, actor, workout_id, params),
    do:
      ExecutionStore.with_user_context(context, fn -> run(context, actor, workout_id, params) end)

  def call(actor, workout_id, params \\ %{}), do: run(nil, actor, workout_id, params)

  defp run(context, actor, workout_id, params) do
    scale_slug = params[:scale] || params["scale"]
    source = params[:source] || params["source"]
    source_reference_id = params[:source_reference_id] || params["source_reference_id"]

    with {:ok, authorized_source} <-
           AuthorizeWorkoutExecutionSource.call(
             context,
             actor,
             workout_id,
             source,
             source_reference_id
           ),
         :ok <- authorize_entitlement(context, actor, authorized_source),
         workout when not is_nil(workout) <- get_workout(context, workout_id),
         {:ok, materialized_workout} <- materialize_workout(workout, scale_slug) do
      {:ok, Execution.build_timer_sequence(materialized_workout)}
    else
      nil -> {:error, :not_found}
      error -> error
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

  defp materialize_workout(workout, nil), do: {:ok, workout}
  defp materialize_workout(workout, ""), do: {:ok, workout}

  defp materialize_workout(workout, scale_slug) do
    available_slugs =
      workout
      |> Map.get(:available_scale_levels, [])
      |> Enum.map(& &1.slug)

    if scale_slug in available_slugs do
      case Workouts.materialize_workout_for_scale(workout.id, scale_slug) do
        nil -> {:error, :invalid_scale_level}
        materialized -> {:ok, materialized}
      end
    else
      {:error, :invalid_scale_level}
    end
  end

  defp get_workout(%{organization_id: _} = context, workout_id),
    do: Workouts.get_workout(context, workout_id)

  defp get_workout(_context, workout_id), do: Workouts.get_workout(workout_id)
end
