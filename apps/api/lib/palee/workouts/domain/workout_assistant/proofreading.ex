defmodule Palee.Workouts.Domain.WorkoutAssistant.Proofreading do
  @moduledoc """
  Verifies the proofreader agent's in-line corrections and turns them into
  actionable issues.

  A correction survives only when its `find` text occurs verbatim in the
  coach's text, differs from its replacement, and does not overlap an earlier
  correction. Each survivor is attached to the canonical field whose value
  contains the same text (so Accept fixes both the text and the field), or
  kept as a text-only fix on the pseudo path `"text"`.
  """

  @kinds ~w(spelling unit number abbreviation format ambiguity)
  @max_corrections 20
  @string_fields ~w(name note tempo)

  def kinds, do: @kinds

  @doc "Verified corrections: `[%{\"find\", \"replace\", \"kind\", \"message\", \"label\", \"offset\"}]`."
  def verify(raw, source) when is_map(raw) and is_binary(source) do
    raw
    |> Map.get("corrections")
    |> List.wrap()
    |> Enum.flat_map(&candidate(&1, source))
    |> Enum.sort_by(& &1["offset"])
    |> drop_overlaps()
    |> Enum.take(@max_corrections)
  end

  def verify(_raw, _source), do: []

  @doc "Issues for corrections, mapped to canonical fields of `workout` when possible."
  def to_issues(corrections, workout) do
    Enum.map(corrections, fn correction ->
      {path, value} = locate(workout, correction)

      %{
        "path" => path,
        "code" => "text_correction",
        "kind" => correction["kind"],
        "severity" =>
          if(correction["kind"] in ~w(ambiguity number unit), do: "warning", else: "info"),
        "required" => false,
        "message" => correction["message"],
        "params" => %{},
        "current_value" => if(path == "text", do: correction["find"], else: get(workout, path)),
        "suggestion" => %{
          "label" => correction["label"],
          "value" => value,
          "text_edit" => %{"find" => correction["find"], "replace" => correction["replace"]}
        }
      }
    end)
  end

  defp candidate(%{} = raw, source) do
    find = raw |> Map.get("find_text") |> string()
    replace = raw |> Map.get("replace_text") |> string()

    with true <- is_binary(find) and is_binary(replace),
         true <- String.trim(find) != "" and find != replace,
         true <- String.length(find) <= 300 and String.length(replace) <= 300,
         {offset, _length} <- :binary.match(source, find) do
      [
        %{
          "find" => find,
          "replace" => replace,
          "offset" => offset,
          "kind" => if(Map.get(raw, "kind") in @kinds, do: raw["kind"], else: "spelling"),
          "message" => raw |> Map.get("message") |> string() |> clip(300),
          "label" => raw |> Map.get("label") |> string() |> clip(60)
        }
      ]
    else
      _rejected -> []
    end
  end

  defp candidate(_raw, _source), do: []

  defp drop_overlaps(corrections) do
    {kept, _end} =
      Enum.reduce(corrections, {[], -1}, fn correction, {acc, last_end} ->
        if correction["offset"] < last_end do
          {acc, last_end}
        else
          {[correction | acc], correction["offset"] + byte_size(correction["find"])}
        end
      end)

    Enum.reverse(kept)
  end

  # Prefer exercise names, then section names, notes and tempo, then title.
  defp locate(workout, %{"find" => find, "replace" => replace}) do
    candidates =
      (workout
       |> Map.get("sections", [])
       |> Enum.with_index()
       |> Enum.flat_map(&section_fields/1)) ++
        [{"title", Map.get(workout, "title")}]

    case Enum.find(candidates, fn {_path, value} ->
           is_binary(value) and String.contains?(value, find)
         end) do
      {path, value} -> {path, String.replace(value, find, replace, global: false)}
      nil -> {"text", nil}
    end
  end

  defp section_fields({section, index}) do
    exercises =
      section
      |> Map.get("exercises", [])
      |> Enum.with_index()
      |> Enum.flat_map(fn {exercise, exercise_index} ->
        Enum.map(@string_fields, fn field ->
          {"sections.#{index}.exercises.#{exercise_index}.#{field}", Map.get(exercise, field)}
        end)
      end)

    exercises ++
      [
        {"sections.#{index}.name", Map.get(section, "name")},
        {"sections.#{index}.note", Map.get(section, "note")}
      ]
  end

  defp get(workout, path) do
    path
    |> String.split(".")
    |> Enum.reduce(workout, fn
      segment, list when is_list(list) -> Enum.at(list, String.to_integer(segment))
      segment, %{} = map -> Map.get(map, segment)
      _segment, _other -> nil
    end)
  end

  defp string(value) when is_binary(value), do: value
  defp string(_value), do: nil

  defp clip(nil, _max), do: nil
  defp clip(value, max), do: value |> String.trim() |> String.slice(0, max)
end
