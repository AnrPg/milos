defmodule MilosTraining.Application.SubmitExecutionNote do
  alias MilosTraining.Execution
  alias MilosTraining.Execution.Domain.AnnotationValidator
  alias MilosTraining.Workouts

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

  defp resolve_workout(%{master_workout_id: workout_id, scale_level_slug: nil}),
    do: Workouts.get_workout(workout_id)

  defp resolve_workout(%{master_workout_id: workout_id, scale_level_slug: ""}),
    do: Workouts.get_workout(workout_id)

  defp resolve_workout(%{master_workout_id: workout_id, scale_level_slug: scale_slug}),
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
         note: note
       }}
    )
  end

  defp enqueue_notification(execution, note) do
    MilosTraining.Notifications.dispatch_event(:workout_note_submitted, %{
      execution_id: execution.id,
      user_id: execution.user_id,
      master_workout_id: execution.master_workout_id,
      note: note
    })
  end
end
