defmodule MilosTraining.Execution.Domain.ModificationPatchValidator do
  @moduledoc """
  Validates actual-workout modification patches.

  Patches describe a concrete expanded workout row and field, preserving the
  canonical value and the user-entered actual value for coach review and
  analytics.
  """

  @types ~w(skipped weight_changed reps_changed time_changed sets_changed exercise_substituted distance_changed calories_changed field_changed other)
  @fields ~w(exercise_name reps load sets duration_seconds distance calories time_cap tempo rest_seconds prescription_value prescription_unit load_mode skipped note)

  def normalize_many(patches) when is_list(patches) do
    patches
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {patch, index}, {:ok, acc} ->
      case normalize(patch, index) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  def normalize_many(_patches), do: {:error, :bad_request}

  def normalize(patch, index \\ 0)

  def normalize(patch, index) when is_map(patch) do
    patch_id = string_value(patch, "patch_id")
    section_id = string_value(patch, "section_id")
    exercise_id = string_value(patch, "exercise_id")
    field = string_value(patch, "field") || legacy_field(patch)
    type = string_value(patch, "type") || infer_type(field)
    canonical_value = value(patch, "canonical_value", value(patch, "prescribed_value"))
    actual_value = value(patch, "actual_value")

    cond do
      patch_id == nil ->
        {:error, :bad_request}

      section_id == nil ->
        {:error, :bad_request}

      exercise_id == nil and field != "sets" ->
        {:error, :bad_request}

      field not in @fields ->
        {:error, :bad_request}

      type not in @types ->
        {:error, :bad_request}

      empty_change?(canonical_value, actual_value, type) ->
        {:error, :bad_request}

      true ->
        {:ok,
         %{
           "patch_id" => patch_id,
           "type" => type,
           "field" => field,
           "section_id" => section_id,
           "section_name" => string_value(patch, "section_name"),
           "segment_key" => string_value(patch, "segment_key"),
           "exercise_id" => exercise_id,
           "exercise_name" => string_value(patch, "exercise_name"),
           "set_index" => int_value(patch, "set_index"),
           "round_index" => int_value(patch, "round_index"),
           "interval_index" => int_value(patch, "interval_index"),
           "row_index" => int_value(patch, "row_index") || index + 1,
           "canonical_value" => canonical_value,
           "actual_value" => actual_value,
           "unit" => string_value(patch, "unit"),
           "note" => string_value(patch, "note")
         }
         |> Enum.reject(fn {_key, val} -> is_nil(val) end)
         |> Map.new()}
    end
  end

  def normalize(_patch, _index), do: {:error, :bad_request}

  defp legacy_field(patch) do
    cond do
      Map.has_key?(patch, "sets") or Map.has_key?(patch, :sets) ->
        "sets"

      Map.has_key?(patch, "actual_mins") or Map.has_key?(patch, :actual_mins) ->
        "duration_seconds"

      true ->
        "prescription_value"
    end
  end

  defp infer_type("reps"), do: "reps_changed"
  defp infer_type("prescription_value"), do: "reps_changed"
  defp infer_type("load"), do: "weight_changed"
  defp infer_type("sets"), do: "sets_changed"
  defp infer_type("duration_seconds"), do: "time_changed"
  defp infer_type("skipped"), do: "skipped"
  defp infer_type("exercise_name"), do: "exercise_substituted"
  defp infer_type(_field), do: "field_changed"

  defp empty_change?(_canonical_value, _actual_value, "skipped"), do: false
  defp empty_change?(canonical_value, actual_value, _type), do: canonical_value == actual_value

  defp string_value(map, key) do
    case fetch_key(map, key) do
      nil ->
        nil

      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      value when is_atom(value) ->
        Atom.to_string(value)

      _other ->
        nil
    end
  end

  defp int_value(map, key) do
    case fetch_key(map, key) do
      value when is_integer(value) and value > 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int > 0 -> int
          _ -> nil
        end

      _other ->
        nil
    end
  end

  defp value(map, key, fallback \\ nil) do
    case fetch_key(map, key) do
      nil -> fallback
      value when is_binary(value) -> String.trim(value)
      value when is_number(value) or is_boolean(value) -> value
      value when is_map(value) -> value
      value when is_list(value) -> value
      value -> to_string(value)
    end
  end

  defp fetch_key(map, key) do
    Map.get(map, key) || Map.get(map, known_atom_key(key))
  end

  defp known_atom_key("patch_id"), do: :patch_id
  defp known_atom_key("type"), do: :type
  defp known_atom_key("field"), do: :field
  defp known_atom_key("section_id"), do: :section_id
  defp known_atom_key("section_name"), do: :section_name
  defp known_atom_key("segment_key"), do: :segment_key
  defp known_atom_key("exercise_id"), do: :exercise_id
  defp known_atom_key("exercise_name"), do: :exercise_name
  defp known_atom_key("set_index"), do: :set_index
  defp known_atom_key("round_index"), do: :round_index
  defp known_atom_key("interval_index"), do: :interval_index
  defp known_atom_key("row_index"), do: :row_index
  defp known_atom_key("canonical_value"), do: :canonical_value
  defp known_atom_key("actual_value"), do: :actual_value
  defp known_atom_key("prescribed_value"), do: :prescribed_value
  defp known_atom_key("actual_mins"), do: :actual_mins
  defp known_atom_key("sets"), do: :sets
  defp known_atom_key("unit"), do: :unit
  defp known_atom_key("note"), do: :note
  defp known_atom_key(_key), do: :__unknown__
end
