defmodule MilosTraining.Workouts.Domain.WorkoutSetComposer do
  @moduledoc """
  Pure normalization and validation for ordered workout items and concrete sets.
  """

  @item_types ["exercise", "header"]
  @progression_modes ["linear", "per_set"]
  @progression_directions ["increase", "decrease"]
  @load_modes ["absolute", "pct_1rm", "bw"]

  alias MilosTraining.Workouts.Domain.WorkoutAuthoringMetadata

  def normalize_items(items) when is_list(items) do
    with {:ok, normalized} <- normalize_each(items),
         :ok <- validate_group_membership(normalized),
         :ok <-
           validate_group_sizes(normalized, :superset_group_id, :superset_requires_multiple_items),
         :ok <-
           validate_group_sizes(
             normalized,
             :alternating_group_id,
             :alternating_group_requires_multiple_items
           ) do
      {:ok, normalized}
    end
  end

  def normalize_items(_items), do: {:error, :invalid_workout_items}

  defp normalize_each(items) do
    items
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {item, order}, {:ok, acc} ->
      case normalize_item(item, order) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_item(item, order) when is_map(item) do
    item_type = value(item, :item_type) || "exercise"

    if item_type in @item_types do
      do_normalize_item(item, order, item_type)
    else
      {:error, :invalid_workout_item_type}
    end
  end

  defp normalize_item(_item, _order), do: {:error, :invalid_workout_item}

  defp do_normalize_item(item, order, "header") do
    normalized =
      item
      |> put(:item_type, "header")
      |> put(:order, order)
      |> put(:sets, nil)
      |> put(:set_prescriptions, [])
      |> put(:load_progression, nil)
      |> put(:superset_group_id, value(item, :superset_group_id))
      |> put(:alternating_group_id, value(item, :alternating_group_id))

    {:ok, normalized}
  end

  defp do_normalize_item(item, order, "exercise") do
    set_count = positive_integer(value(item, :sets)) || inferred_set_count(item) || 1

    with {:ok, progression} <- normalize_progression(value(item, :load_progression)),
         {:ok, set_prescriptions} <- normalize_set_prescriptions(item, set_count, progression) do
      normalized =
        item
        |> put(:item_type, "exercise")
        |> put(:order, order)
        |> put(:sets, set_count)
        |> put(:load_progression, progression)
        |> put(:set_prescriptions, set_prescriptions)
        |> put(:superset_group_id, value(item, :superset_group_id))
        |> put(:alternating_group_id, value(item, :alternating_group_id))

      {:ok, normalized}
    end
  end

  defp normalize_progression(nil), do: {:ok, nil}

  defp normalize_progression(progression) when is_map(progression) do
    mode = value(progression, :mode) || "linear"
    direction = value(progression, :direction) || "increase"
    start_mode = value(progression, :start_mode) || "absolute"

    cond do
      mode not in @progression_modes ->
        {:error, :invalid_load_progression_mode}

      direction not in @progression_directions ->
        {:error, :invalid_load_progression_direction}

      start_mode not in @load_modes ->
        {:error, :invalid_load_mode}

      true ->
        {:ok,
         %{
           "mode" => mode,
           "direction" => direction,
           "start_value" => non_negative_number(value(progression, :start_value)) || 0,
           "start_mode" => start_mode,
           "step_value" => non_negative_number(value(progression, :step_value)) || 0,
           "per_set_values" =>
             progression
             |> value(:per_set_values)
             |> normalize_per_set_values()
         }}
    end
  end

  defp normalize_progression(_progression), do: {:error, :invalid_load_progression}

  defp normalize_set_prescriptions(item, set_count, progression) do
    raw = value(item, :set_prescriptions)

    prescriptions =
      if is_list(raw) and raw != [] do
        raw
      else
        List.duplicate(%{}, set_count)
      end

    if length(prescriptions) != set_count do
      {:error, :set_prescription_count_mismatch}
    else
      prescriptions
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {prescription, set_index}, {:ok, acc} ->
        case normalize_set_prescription(prescription, item, progression, set_index) do
          {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, normalized} ->
          normalized = Enum.reverse(normalized)
          indexes = Enum.map(normalized, & &1.set_index)

          if indexes == Enum.to_list(1..set_count) do
            {:ok, normalized}
          else
            {:error, :invalid_set_indexes}
          end

        error ->
          error
      end
    end
  end

  defp normalize_set_prescription(prescription, item, progression, set_index)
       when is_map(prescription) do
    requested_index = positive_integer(value(prescription, :set_index)) || set_index

    load_value =
      value(prescription, :load_value) ||
        progression_value(progression, set_index) ||
        value(item, :load_value)

    load_mode =
      value(prescription, :load_mode) ||
        progression_mode(progression) ||
        value(item, :load_mode)

    metadata = value(prescription, :metadata) || %{}

    case WorkoutAuthoringMetadata.validate(:set, metadata) do
      :ok ->
        {:ok,
         %{
           set_index: requested_index,
           prescription_value:
             value(prescription, :prescription_value) || value(item, :prescription_value),
           prescription_unit:
             value(prescription, :prescription_unit) || value(item, :prescription_unit),
           load_value: load_value,
           load_mode: load_mode,
           note: value(prescription, :note),
           metadata: WorkoutAuthoringMetadata.normalize_keys(metadata)
         }}

      {:error, _reason} ->
        {:error, :invalid_set_prescription_metadata}
    end
  end

  defp normalize_set_prescription(_prescription, _item, _progression, _set_index),
    do: {:error, :invalid_set_prescription}

  defp progression_value(nil, _set_index), do: nil

  defp progression_value(%{"mode" => "per_set"} = progression, set_index) do
    Enum.at(progression["per_set_values"], set_index - 1) || progression["start_value"]
  end

  defp progression_value(progression, set_index) do
    multiplier = if progression["direction"] == "decrease", do: -1, else: 1

    (progression["start_value"] + multiplier * progression["step_value"] * (set_index - 1))
    |> max(0)
  end

  defp progression_mode(nil), do: nil
  defp progression_mode(progression), do: progression["start_mode"]

  defp validate_group_membership(items) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      superset_group_id = value(item, :superset_group_id)
      alternating_group_id = value(item, :alternating_group_id)

      cond do
        value(item, :item_type) == "header" and
            (superset_group_id || alternating_group_id) ->
          {:halt, {:error, :header_cannot_join_set_group}}

        superset_group_id && alternating_group_id ->
          {:halt, {:error, :ambiguous_set_group}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_group_sizes(items, field, error) do
    invalid? =
      items
      |> Enum.reject(&is_nil(value(&1, field)))
      |> Enum.group_by(&value(&1, field))
      |> Enum.any?(fn {_group_id, members} -> length(members) < 2 end)

    if invalid?, do: {:error, error}, else: :ok
  end

  defp inferred_set_count(item) do
    case value(item, :set_prescriptions) do
      prescriptions when is_list(prescriptions) and prescriptions != [] -> length(prescriptions)
      _ -> nil
    end
  end

  defp normalize_per_set_values(values) when is_list(values) do
    Enum.map(values, &(non_negative_number(&1) || 0))
  end

  defp normalize_per_set_values(_values), do: []

  defp positive_integer(value) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value), do: nil

  defp non_negative_number(value) when is_number(value) and value >= 0, do: value
  defp non_negative_number(_value), do: nil

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp put(map, key, value) do
    map
    |> Map.delete(Atom.to_string(key))
    |> Map.put(key, value)
  end
end
