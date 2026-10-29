defmodule Palee.Imports.Domain.HeaderMatcher do
  @moduledoc """
  ADR-254: a proposed mapping from a file's header row. Pure.

  Each column gets the field whose names (of the chosen preset, vendor
  names first, then the generic ones) contain its normalized header; a
  column matching several fields takes the one where it ranks highest, and
  a field goes to one column only (the first). With no preset (`nil`) the
  preset that maps the most columns is chosen, `excel` on a tie.
  """

  alias Palee.Imports.Domain.Presets

  @doc """
  `%{source, date_order, mapping}`; `mapping` is one
  `%{column, header, field}` per column (`field` nil when unmapped).
  """
  def suggest(header, preset_key \\ nil) when is_list(header) do
    presets =
      case preset_key && Presets.fetch(preset_key) do
        {:ok, preset} -> [preset]
        _auto -> Presets.all()
      end

    {preset, mapping} =
      presets
      |> Enum.map(&{&1, map_columns(header, &1)})
      |> Enum.max_by(fn {preset, mapping} ->
        {Enum.count(mapping, & &1.field), if(preset.key == "excel", do: 1, else: 0)}
      end)

    %{source: preset.key, date_order: preset.date_order, mapping: mapping}
  end

  defp map_columns(header, preset) do
    candidates =
      header
      |> Enum.with_index()
      |> Enum.flat_map(fn {name, column} ->
        normalized = Presets.normalize(name || "")

        Enum.flat_map(preset.headers, fn {field, names} ->
          case Enum.find_index(names, &(&1 == normalized)) do
            nil -> []
            rank -> [{rank, column, field}]
          end
        end)
      end)
      |> Enum.sort()

    {assigned, _taken} =
      Enum.reduce(candidates, {%{}, MapSet.new()}, fn {_rank, column, field}, {assigned, taken} ->
        if Map.has_key?(assigned, column) or MapSet.member?(taken, field),
          do: {assigned, taken},
          else: {Map.put(assigned, column, field), MapSet.put(taken, field)}
      end)

    header
    |> Enum.with_index()
    |> Enum.map(fn {name, column} ->
      %{column: column, header: name, field: Map.get(assigned, column)}
    end)
  end
end
