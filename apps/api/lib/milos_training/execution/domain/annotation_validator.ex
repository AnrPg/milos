defmodule MilosTraining.Execution.Domain.AnnotationValidator do
  @moduledoc false

  def validate(workout, params) when is_map(workout) and is_map(params) do
    exercise_id = params[:exercise_id] || params["exercise_id"]

    with exercise when not is_nil(exercise) <- find_exercise(workout, exercise_id),
         {:ok, start_pos, end_pos} <- selection_range(params),
         selected_text when is_binary(selected_text) <-
           params[:selected_text] || params["selected_text"],
         true <- selected_text == String.slice(exercise.name, start_pos, end_pos - start_pos) do
      :ok
    else
      _ -> {:error, :bad_request}
    end
  end

  def validate(_workout, _params), do: {:error, :bad_request}

  defp find_exercise(workout, exercise_id) when is_binary(exercise_id) do
    workout
    |> Map.get(:sections, Map.get(workout, "sections", []))
    |> flatten_exercises()
    |> Enum.find(fn exercise ->
      to_string(exercise[:id] || exercise["id"]) == exercise_id
    end)
    |> case do
      nil ->
        nil

      exercise ->
        %{name: exercise[:name] || exercise["name"] || ""}
    end
  end

  defp find_exercise(_workout, _exercise_id), do: nil

  defp flatten_exercises(sections) do
    Enum.flat_map(sections, fn section ->
      (section[:exercises] || section["exercises"] || []) ++
        flatten_exercises(section[:sections] || section["sections"] || [])
    end)
  end

  defp selection_range(params) do
    start_pos = params[:selection_start] || params["selection_start"]
    end_pos = params[:selection_end] || params["selection_end"]

    if is_integer(start_pos) and is_integer(end_pos) and start_pos >= 0 and end_pos > start_pos do
      {:ok, start_pos, end_pos}
    else
      {:error, :bad_request}
    end
  end
end
