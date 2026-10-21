defmodule MilosTraining.VoiceLog.Domain.Draft do
  @moduledoc """
  Turns the parser's answer into a draft training-log entry (ADR-175), pure.

  The parser is untrusted input: every field is optional, trimmed, capped
  and range-checked; anything out of range becomes `nil` (or is dropped, for
  an exercise without a name). The draft is never saved here: the member
  reviews and edits it in the log form, and only their confirmation creates
  an entry through the normal training-log command.

  When the parser fails, `from_transcript/1` keeps the member's words as the
  entry's note, so recording is never wasted.
  """

  @max_exercises 30
  @load_units ~w(kg lb)

  def empty do
    %{
      title: nil,
      duration_minutes: nil,
      perceived_effort: nil,
      days_ago: nil,
      notes: nil,
      exercises: []
    }
  end

  @doc "The draft from a parser answer, or `{:error, :parser_invalid_response}`."
  def normalize(%{} = raw) do
    case field(raw, :exercises) do
      exercises when is_list(exercises) or is_nil(exercises) ->
        {:ok,
         %{
           title: text(field(raw, :title), 160),
           duration_minutes: integer(field(raw, :duration_minutes), 1, 24 * 60),
           perceived_effort: integer(field(raw, :perceived_effort), 1, 10),
           days_ago: integer(field(raw, :days_ago), 0, 14),
           notes: text(field(raw, :notes), 1_000),
           exercises:
             (exercises || [])
             |> Enum.filter(&is_map/1)
             |> Enum.map(&exercise/1)
             |> Enum.reject(&is_nil/1)
             |> Enum.take(@max_exercises)
         }}

      _other ->
        {:error, :parser_invalid_response}
    end
  end

  def normalize(_raw), do: {:error, :parser_invalid_response}

  @doc "A draft that only carries the transcript as its note."
  def from_transcript(transcript), do: %{empty() | notes: text(transcript, 1_000)}

  @doc "The transcript as text the member may see: trimmed, capped, or nil when empty."
  def transcript(text) when is_binary(text), do: text(text, 2_000)
  def transcript(_text), do: nil

  defp exercise(raw) do
    case text(field(raw, :name), 120) do
      nil ->
        nil

      name ->
        load = number(field(raw, :load), 0, 1_000)

        %{
          name: name,
          sets: integer(field(raw, :sets), 1, 100),
          reps: integer(field(raw, :reps), 1, 1_000),
          load: load,
          load_unit: if(load, do: unit(field(raw, :load_unit)), else: nil)
        }
    end
  end

  defp unit(value) when value in @load_units, do: value
  defp unit(_value), do: "kg"

  defp text(value, max) when is_binary(value) do
    case value |> String.replace(~r/\s+/u, " ") |> String.trim() do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, max)
    end
  end

  defp text(_value, _max), do: nil

  defp integer(value, min, max) when is_integer(value) and value >= min and value <= max,
    do: value

  defp integer(value, min, max) when is_float(value) do
    rounded = round(value)
    if rounded == value, do: integer(rounded, min, max), else: nil
  end

  defp integer(_value, _min, _max), do: nil

  defp number(value, min, max) when is_number(value) and value >= min and value <= max,
    do: if(is_float(value), do: Float.round(value, 2), else: value)

  defp number(_value, _min, _max), do: nil

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
