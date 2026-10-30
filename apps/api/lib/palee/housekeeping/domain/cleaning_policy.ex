defmodule Palee.Housekeeping.Domain.CleaningPolicy do
  @moduledoc "Rules of the cleaning log (ADR-102)."

  def can_start?(%{archived_at: nil}), do: :ok
  def can_start?(_area), do: {:error, :cleaning_area_archived}

  @doc "Finishing keeps only the area's own tasks, in the area's order."
  def finish(entry, area, tasks_done, finished_at) do
    cond do
      not is_nil(entry.finished_at) ->
        {:error, :cleaning_already_finished}

      DateTime.compare(finished_at, entry.started_at) == :lt ->
        {:error, :cleaning_finished_before_start}

      true ->
        done = List.wrap(tasks_done)
        {:ok, Enum.filter(area.tasks, &(&1 in done))}
    end
  end

  @statuses ~w(cleaned not_cleaned)

  @doc """
  ADR-290: the answers for a room's visual checklist. Every point is
  answered once, «Καθαρό» (`cleaned`) or «Δεν καθαρίστηκε» (`not_cleaned`);
  a point not cleaned needs a note saying why. Returns the results in the
  points' order, each keeping the point's instruction and photo as they
  were, so the log still reads right after the point changes.

  `points` are `%{id, instruction, media_id}`; `results` are maps with
  `point_id`, `status`, `note` and `after_media_id` (atom or string keys).
  """
  def point_results([], _results), do: {:ok, []}

  def point_results(points, results) when is_list(results) do
    by_point = Map.new(results, &{field(&1, :point_id), &1})

    cond do
      length(results) != map_size(by_point) ->
        {:error, :invalid_point_results}

      Enum.any?(Map.keys(by_point), fn id -> not Enum.any?(points, &(&1.id == id)) end) ->
        {:error, :invalid_point_results}

      true ->
        points
        |> Enum.reduce_while({:ok, []}, fn point, {:ok, acc} ->
          case result(point, Map.get(by_point, point.id)) do
            {:ok, row} -> {:cont, {:ok, [row | acc]}}
            error -> {:halt, error}
          end
        end)
        |> case do
          {:ok, rows} -> {:ok, Enum.reverse(rows)}
          error -> error
        end
    end
  end

  def point_results(_points, _results), do: {:error, :invalid_point_results}

  @doc "The results of the points left not cleaned."
  def not_cleaned(results), do: Enum.filter(results, &(&1["status"] == "not_cleaned"))

  defp result(_point, nil), do: {:error, :cleaning_point_unanswered}

  defp result(point, answer) do
    status = answer |> field(:status) |> to_string_or_nil()
    note = answer |> field(:note) |> trim()

    cond do
      status not in @statuses ->
        {:error, :invalid_point_results}

      status == "not_cleaned" and is_nil(note) ->
        {:error, :cleaning_point_note_required}

      is_binary(note) and String.length(note) > 1_000 ->
        {:error, :invalid_point_results}

      true ->
        {:ok,
         %{
           "point_id" => point.id,
           "instruction" => point.instruction,
           "media_id" => point.media_id,
           "status" => status,
           "note" => note,
           "after_media_id" => field(answer, :after_media_id)
         }}
    end
  end

  defp field(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value) when is_atom(value), do: Atom.to_string(value)
  defp to_string_or_nil(value) when is_binary(value), do: value
  defp to_string_or_nil(_value), do: nil

  defp trim(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim(_value), do: nil
end
