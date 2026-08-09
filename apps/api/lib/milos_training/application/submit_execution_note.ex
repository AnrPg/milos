defmodule MilosTraining.Application.SubmitExecutionNote do
  alias MilosTraining.Execution
  alias MilosTraining.Execution.ExecutionStore
  alias MilosTraining.Execution.Domain.AnnotationValidator
  alias MilosTraining.Workouts

  def call(context, execution_id, user_id, params),
    do: ExecutionStore.with_user_context(context, fn -> call(execution_id, user_id, params) end)

  def call(execution_id, user_id, params) do
    params_with_id = ensure_note_id(params)
    note_id = to_string(Map.get(params_with_id, :id) || Map.get(params_with_id, "id"))

    with execution when not is_nil(execution) <- Execution.get_execution(execution_id),
         workout when not is_nil(workout) <- resolve_workout(execution),
         :ok <- AnnotationValidator.validate(workout, params_with_id),
         {:ok, execution} <-
           Execution.submit_execution_note(execution_id, user_id, params_with_id) do
      case find_note(execution.exercise_notes || [], note_id) do
        nil ->
          {:ok, execution}

        note ->
          enqueue_notification(execution, note)
          broadcast_note_submission(execution, note)
          {:ok, execution}
      end
    end
  end

  defp resolve_workout(%{master_workout_id: nil}), do: nil

  defp resolve_workout(%{
         master_workout_id: workout_id,
         scale_level_slug: scale_slug,
         organization_id: organization_id,
         user_id: user_id
       }) do
    # See MilosTraining.Application.UpdateExecutionProgress: the /api/executions
    # routes are user-scoped, not org-scoped, so the outer context here never
    # carries an organization_id. Re-open the tenant scope using the
    # execution's own organization so the workout lookup below can see it.
    Workouts.with_tenant_context(%{organization_id: organization_id, user_id: user_id}, fn ->
      resolve_workout_in_tenant(workout_id, scale_slug)
    end)
  end

  defp resolve_workout_in_tenant(workout_id, nil), do: Workouts.get_workout(workout_id)
  defp resolve_workout_in_tenant(workout_id, ""), do: Workouts.get_workout(workout_id)

  defp resolve_workout_in_tenant(workout_id, scale_slug),
    do: Workouts.materialize_workout_for_scale(workout_id, scale_slug)

  defp ensure_note_id(%{} = params) do
    if Map.has_key?(params, :id) or Map.has_key?(params, "id") do
      params
    else
      Map.put(params, "id", Ecto.UUID.generate())
    end
  end

  defp find_note(notes, note_id) do
    Enum.find(notes, fn note ->
      to_string(note["id"] || note[:id]) == note_id
    end)
  end

  defp broadcast_note_submission(execution, note) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "workout:note_submitted",
      {:workout_note_submitted,
       %{
         execution_id: execution.id,
         user_id: execution.user_id,
         master_workout_id: execution.master_workout_id,
         organization_id: execution.organization_id,
         note: note
       }}
    )
  end

  defp enqueue_notification(execution, note) do
    # Notifications.staff_recipients/1 (used by enqueue_workout_note/1) looks
    # up admins by `organization_id`; without it here the recipient list is
    # always empty and no admin is ever notified of a submitted note.
    MilosTraining.Notifications.dispatch_event(:workout_note_submitted, %{
      execution_id: execution.id,
      user_id: execution.user_id,
      master_workout_id: execution.master_workout_id,
      organization_id: execution.organization_id,
      note: note
    })
  end
end
