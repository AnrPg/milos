defmodule Palee.Scaling.Domain.Advice do
  @moduledoc """
  Validates what the scaling advisor answered (ADR-174), pure.

  The advisor is untrusted input. Only changes to movements that exist in
  the programmed workout survive (one per movement, at most 12); texts are
  trimmed and capped; a scale level must be one of the gym's active levels.
  The result is either `{:ok, advice}` with at least one change or a scale
  level, `{:ok, :no_change}`, or `{:error, :advisor_invalid_response}`.
  """

  @changes ~w(substitute load reps skip other)
  @max_items 12

  def changes, do: @changes

  def normalize(%{} = raw, movements, scale_levels) do
    by_id = Map.new(movements, &{&1.id, &1})
    slugs = Enum.map(scale_levels, &to_string(field(&1, :slug)))

    case field(raw, :items) do
      items when is_list(items) ->
        normalized =
          items
          |> Enum.filter(&is_map/1)
          |> Enum.map(&item(&1, by_id))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq_by(& &1.exercise_id)
          |> Enum.take(@max_items)
          |> Enum.with_index(1)
          |> Enum.map(fn {item, index} -> Map.put(item, :id, "i#{index}") end)

        scale = field(raw, :scale_level)
        scale = if is_binary(scale) and scale in slugs, do: scale, else: nil

        if normalized == [] and is_nil(scale),
          do: {:ok, :no_change},
          else:
            {:ok,
             %{
               summary: text(field(raw, :summary), 600),
               scale_level_slug: scale,
               items: normalized
             }}

      _missing ->
        {:error, :advisor_invalid_response}
    end
  end

  def normalize(_raw, _movements, _scale_levels), do: {:error, :advisor_invalid_response}

  defp item(raw, by_id) do
    change = field(raw, :change)
    movement = Map.get(by_id, to_string(field(raw, :exercise_id)))
    suggested = text(field(raw, :suggested), 120)
    reason = text(field(raw, :reason), 240)

    cond do
      is_nil(movement) or change not in @changes or is_nil(reason) -> nil
      change != "skip" and is_nil(suggested) -> nil
      true -> build(movement, change, suggested, reason)
    end
  end

  defp build(movement, change, suggested, reason) do
    %{
      exercise_id: movement.id,
      section_id: movement.section_id,
      section_name: movement.section_name,
      exercise_name: movement.name,
      prescribed: movement.prescription,
      change: change,
      suggested: if(change == "skip", do: nil, else: suggested),
      reason: reason
    }
  end

  defp text(value, max) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, max)
    end
  end

  defp text(_value, _max), do: nil

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp field(_map, _key), do: nil
end
