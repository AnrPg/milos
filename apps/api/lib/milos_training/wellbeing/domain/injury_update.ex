defmodule MilosTraining.Wellbeing.Domain.InjuryUpdate do
  @moduledoc """
  An injury update (ADR-140 §3): optional text plus the field changes it
  makes. It becomes one `updated` event on the injury's timeline, carrying
  `%{"note" => text, "changes" => [%{"field", "from", "to"}]}`; fields that
  did not change are not recorded. An update with neither text nor a change
  is refused.
  """

  @fields ~w(severity body_area training_limitations description tags)
  @note_max 2000

  def fields, do: @fields

  @doc "Returns the report attrs to write and the event payload, or an error."
  def build(injury, params) when is_map(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)
    note = params |> Map.get("note") |> blank_to_nil()

    attrs =
      for field <- @fields, Map.has_key?(params, field), into: %{} do
        {field, normalize(field, Map.get(params, field))}
      end

    changes =
      Enum.flat_map(attrs, fn {field, to} ->
        case Map.get(injury, String.to_existing_atom(field)) do
          ^to -> []
          from -> [%{"field" => field, "from" => from, "to" => to}]
        end
      end)

    cond do
      is_binary(note) and String.length(note) > @note_max -> {:error, :note_too_long}
      is_nil(note) and changes == [] -> {:error, :empty_update}
      true -> {:ok, Map.new(changes, &{&1["field"], &1["to"]}), payload(note, sort(changes))}
    end
  end

  defp payload(note, changes), do: %{"note" => note, "changes" => changes}

  defp sort(changes),
    do: Enum.sort_by(changes, &Enum.find_index(@fields, fn f -> f == &1["field"] end))

  defp normalize("tags", tags) when is_list(tags),
    do: tags |> Enum.map(&blank_to_nil/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp normalize("tags", _tags), do: []
  defp normalize(_field, value), do: blank_to_nil(value)

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
