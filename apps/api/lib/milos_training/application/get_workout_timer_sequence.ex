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
         {:ok, execution_context} <- finance_context(context, authorized_source),
         :ok <- authorize_entitlement(execution_context, actor, authorized_source) do
      # The /api/workouts/:id/timer-sequence route is user-scoped, not
      # org-scoped, so `context` never carries an organization_id. Re-open
      # the tenant scope using the organization AuthorizeWorkoutExecutionSource
      # just derived so the workout lookup below can see it.
      with %{} = workout <- Workouts.get_workout(execution_context, workout_id) || :not_found,
           {:ok, materialized_workout} <-
             materialize_workout(workout, scale_slug) do
        {:ok,
         %{
           segments: Execution.build_timer_sequence(materialized_workout),
           content: content(materialized_workout, authorized_source)
         }}
      else
        :not_found -> {:error, :not_found}
        error -> error
      end
    end
  end

  # What the member reads before Έναρξη (ADR-140 §4): the assignment's and
  # the workout's Οδηγίες, then each section's. Members never get a
  # coach-brief: the workout was read for the member audience.
  defp content(workout, authorized_source) do
    %{
      assignment_instructions: Map.get(authorized_source, :instructions),
      workout: Map.get(workout, :content, []),
      sections:
        workout
        |> Map.get(:sections, [])
        |> Enum.map(&%{id: &1.id, name: &1.name, content: Map.get(&1, :content, [])})
        |> Enum.reject(&(&1.content == []))
    }
  end

  defp authorize_entitlement(execution_context, actor, authorized_source) do
    request = AuthorizeFinanceEntitlement.execution_request(authorized_source)

    case AuthorizeFinanceEntitlement.call(execution_context, actor, request) do
      {:ok, _decision} -> :ok
      result -> result
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

    # The workout was already read in the execution's tenant; materialize it
    # in place rather than reading it again (ADR-128).
    if scale_slug in available_slugs do
      {:ok, Workouts.materialize_for_scale(workout, scale_slug)}
    else
      {:error, :invalid_scale_level}
    end
  end
end
