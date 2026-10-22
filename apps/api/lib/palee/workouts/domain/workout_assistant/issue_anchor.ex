defmodule Palee.Workouts.Domain.WorkoutAssistant.IssueAnchor do
  @moduledoc """
  The words of the coach's text an assistant issue is about (its anchor), so
  the editor can mark them in place and open the issue right above them.
  Pure.

  In order of trust: the words a text fix replaces, the words the assistant
  quoted (`source_text`), then the name of the exercise or section the
  issue's path points at. An anchor is always a slice of the source exactly
  as written (case included); nil when no words can be found, and the issue
  then stays in the side panel only.
  """

  @max_length 200

  @doc "The anchor for `issue` (a normalized issue map) in `source`, or nil."
  def find(%{} = issue, %{} = workout, quote, source) when is_binary(source) do
    [
      get_in(issue, ["suggestion", "text_edit", "find"]),
      quote | path_words(issue["path"], workout)
    ]
    |> Enum.find_value(&locate(&1, source))
  end

  def find(_issue, _workout, _quote, _source), do: nil

  # The exercise, then the section, the path sits in; a top-level field's own
  # value (a title the coach wrote) otherwise.
  defp path_words(path, workout) when is_binary(path) do
    case String.split(path, ".") do
      ["sections", section, "exercises", exercise | _rest] ->
        [
          at(workout, ["sections", section, "exercises", exercise, "name"]),
          at(workout, ["sections", section, "name"])
        ]

      ["sections", section | _rest] ->
        [at(workout, ["sections", section, "name"])]

      [field] ->
        [at(workout, [field])]

      _other ->
        []
    end
  end

  defp path_words(_path, _workout), do: []

  defp at(value, []), do: value

  defp at(list, [index | rest]) when is_list(list) do
    case Integer.parse(index) do
      {position, ""} -> list |> Enum.at(position) |> at(rest)
      _other -> nil
    end
  end

  defp at(%{} = map, [key | rest]), do: map |> Map.get(key) |> at(rest)
  defp at(_value, _path), do: nil

  # The words as the source writes them: exact first, then ignoring case.
  defp locate(words, source) when is_binary(words) do
    words = String.trim(words)

    cond do
      words == "" or String.length(words) > @max_length ->
        nil

      String.contains?(source, words) ->
        words

      true ->
        case Regex.run(~r/#{Regex.escape(words)}/iu, source) do
          [match] -> match
          _none -> nil
        end
    end
  end

  defp locate(_words, _source), do: nil
end
