defmodule MilosTraining.Execution.Commands.SubmitExecutionNote do
  alias MilosTraining.Execution.ExecutionStore

  def call(execution_id, user_id, params) do
    with {:ok, execution} <- fetch_owned_execution(execution_id, user_id),
         :ok <- ensure_mutable(execution),
         {:ok, note} <- normalize_note(params) do
      updated_notes = upsert_note(execution.exercise_notes || [], note)
      ExecutionStore.update_execution(execution.id, %{exercise_notes: updated_notes})
    end
  end

  defp fetch_owned_execution(execution_id, user_id) do
    case ExecutionStore.get_execution(execution_id) do
      nil -> {:error, :not_found}
      %{user_id: ^user_id} = execution -> {:ok, execution}
      %{} -> {:error, :forbidden}
    end
  end

  defp ensure_mutable(%{completed_at_utc: nil}), do: :ok
  defp ensure_mutable(_execution), do: {:error, :already_completed}

  defp normalize_note(params) do
    note_id = params[:id] || params["id"] || Ecto.UUID.generate()
    exercise_id = params[:exercise_id] || params["exercise_id"]
    selected_text = params[:selected_text] || params["selected_text"]
    selection_start = params[:selection_start] || params["selection_start"]
    selection_end = params[:selection_end] || params["selection_end"]
    tags = params[:tags] || params["tags"] || []
    note_text = params[:note_text] || params["note_text"]

    cond do
      not is_binary(exercise_id) or exercise_id == "" ->
        {:error, :bad_request}

      blank?(selected_text) ->
        {:error, :bad_request}

      invalid_tags?(tags) ->
        {:error, :bad_request}

      invalid_selection_range?(selection_start, selection_end) ->
        {:error, :bad_request}

      Enum.empty?(normalize_tags(tags)) and blank?(note_text) ->
        {:error, :bad_request}

      true ->
        timestamp = DateTime.utc_now()

        {:ok,
         %{
           id: note_id,
           exercise_id: exercise_id,
           selected_text: normalize_optional(selected_text),
           selection_start: normalize_integer(selection_start),
           selection_end: normalize_integer(selection_end),
           tags: normalize_tags(tags),
           note_text: normalize_optional(note_text),
           updated_at: timestamp
         }}
    end
  end

  defp upsert_note(notes, note) do
    normalized_notes = Enum.map(notes, &normalize_existing_note/1)

    case Enum.find_index(normalized_notes, &same_note?(&1, note.id)) do
      nil ->
        normalized_notes ++ [Map.put(note, :inserted_at, note.updated_at)]

      index ->
        existing = Enum.at(normalized_notes, index)

        merged =
          note
          |> Map.put(
            :inserted_at,
            existing[:inserted_at] || existing["inserted_at"] || note.updated_at
          )

        List.replace_at(normalized_notes, index, merged)
    end
  end

  defp normalize_existing_note(note) when is_map(note) do
    %{
      id: note["id"] || note[:id] || Ecto.UUID.generate(),
      exercise_id: note["exercise_id"] || note[:exercise_id],
      selected_text: note["selected_text"] || note[:selected_text] || note["word"] || note[:word],
      selection_start: note["selection_start"] || note[:selection_start],
      selection_end: note["selection_end"] || note[:selection_end],
      tags:
        cond do
          is_list(note["tags"]) -> normalize_tags(note["tags"])
          is_list(note[:tags]) -> normalize_tags(note[:tags])
          legacy_word = note["word"] || note[:word] -> normalize_tags([legacy_word])
          true -> []
        end,
      note_text: note["note_text"] || note[:note_text],
      inserted_at: note["inserted_at"] || note[:inserted_at],
      updated_at: note["updated_at"] || note[:updated_at]
    }
  end

  defp same_note?(note, note_id) do
    note["id"] == note_id || note[:id] == note_id
  end

  defp blank?(value), do: normalize_optional(value) == nil

  defp invalid_tags?(tags),
    do: not is_list(tags) or Enum.any?(tags, &(normalize_optional(&1) == nil))

  defp invalid_selection_range?(nil, nil), do: false

  defp invalid_selection_range?(selection_start, selection_end) do
    with start when is_integer(start) <- normalize_integer(selection_start),
         end_pos when is_integer(end_pos) <- normalize_integer(selection_end) do
      start < 0 or end_pos <= start
    else
      _ -> true
    end
  end

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.map(&normalize_optional/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp normalize_integer(_value), do: nil

  defp normalize_optional(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional(_value), do: nil
end
