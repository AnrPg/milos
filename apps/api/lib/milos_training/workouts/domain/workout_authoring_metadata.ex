defmodule MilosTraining.Workouts.Domain.WorkoutAuthoringMetadata do
  @moduledoc """
  Pure validation for bounded rich workout metadata and typed notes.

  Metadata maps are canonical extension points, not arbitrary storage. Every
  accepted key and value kind is registered here so structured authoring, DSL
  publication, and persistence share the same boundary.
  """

  @note_types ~w(note coach-note athlete-note safety-note scaling-note equipment-note)

  @specs %{
    workout: %{
      "target_population" => :short_string,
      "objective" => :short_string,
      "location" => :short_string,
      "modality" => :short_string,
      "program_position" => :short_string,
      "default_scale" => :slug,
      "source_revision" => :non_negative_integer,
      "schema_version" => :positive_integer
    },
    section: %{
      "composition" => {:enum, ~w(straight_sets rounds circuit stations)},
      "rounds" => :positive_integer,
      "rest_between_exercises_seconds" => :non_negative_integer,
      "rest_between_rounds_seconds" => :non_negative_integer,
      "rest_between_groups_seconds" => :non_negative_integer,
      "transition_seconds" => :non_negative_integer,
      "auto_advance" => :boolean,
      "recovery_condition" => :short_string,
      "target_condition" => :short_string,
      "score_label" => :short_string
    },
    exercise: %{
      "distance_meters" => :positive_number,
      "target_rpe" => {:number_range, 0, 10},
      "target_rir" => :non_negative_integer,
      "load_unit" => {:enum, ~w(kg lb bodyweight pct_1rm)},
      "percentage_of" => :short_string,
      "pace" => :short_string,
      "cadence" => :positive_integer,
      "target_heart_rate_bpm" => :positive_integer,
      "side" => {:enum, ~w(left right both each alternating)},
      "stance" => :short_string,
      "grip" => :short_string,
      "range_of_motion" => :short_string,
      "height_cm" => :positive_number,
      "incline_percent" => :non_negative_number,
      "resistance" => :short_string,
      "equipment" => :string_list,
      "variation" => :short_string,
      "score_contribution" => :short_string,
      "transition_seconds" => :non_negative_integer,
      "rest_between_reps_seconds" => :non_negative_integer,
      "rest_between_exercises_seconds" => :non_negative_integer,
      "rest_between_rounds_seconds" => :non_negative_integer,
      "rest_between_groups_seconds" => :non_negative_integer,
      "rest_between_sides_seconds" => :non_negative_integer,
      "rest_after_exercise_seconds" => :non_negative_integer,
      "rest_until" => :short_string,
      "rest_range_seconds" => :duration_range,
      "deload" => :boolean,
      "catalog_alias" => :short_string
    },
    group: %{
      "type" => {:enum, ~w(superset alternating)},
      "title" => :short_string,
      "sets" => :positive_integer,
      "rest_between_groups_seconds" => :non_negative_integer,
      "notes" => :notes
    },
    set: %{
      "load_unit" => {:enum, ~w(kg lb bodyweight pct_1rm)},
      "tempo" => :short_string,
      "target_rpe" => {:number_range, 0, 10},
      "target_rir" => :non_negative_integer,
      "distance_meters" => :positive_number,
      "rest_after_seconds" => :non_negative_integer,
      "deload" => :boolean,
      "side" => {:enum, ~w(left right both each alternating)}
    }
  }

  def note_types, do: @note_types
  def keys(scope), do: @specs |> Map.fetch!(scope) |> Map.keys()

  def validate(scope, metadata) when is_map(metadata) do
    specs = Map.fetch!(@specs, scope)

    Enum.reduce_while(metadata, :ok, fn {raw_key, value}, :ok ->
      key = to_string(raw_key)

      case Map.fetch(specs, key) do
        {:ok, kind} ->
          if valid_value?(kind, value),
            do: {:cont, :ok},
            else: {:halt, {:error, {:invalid_metadata_value, key}}}

        :error ->
          {:halt, {:error, {:unknown_metadata_key, key}}}
      end
    end)
  end

  def validate(_scope, _metadata), do: {:error, :metadata_must_be_an_object}

  def validate_notes(notes) when is_list(notes) do
    if Enum.all?(notes, &valid_note?/1), do: :ok, else: {:error, :invalid_typed_note}
  end

  def validate_notes(_notes), do: {:error, :notes_must_be_a_list}

  def normalize_keys(metadata) when is_map(metadata) do
    Map.new(metadata, fn {key, value} -> {to_string(key), value} end)
  end

  defp valid_note?(note) when is_map(note) do
    type = Map.get(note, :type) || Map.get(note, "type")
    body = Map.get(note, :body) || Map.get(note, "body")
    document = Map.get(note, :document) || Map.get(note, "document")

    type in @note_types and is_binary(body) and byte_size(body) in 1..20_000 and
      (is_nil(document) or is_map(document))
  end

  defp valid_note?(_note), do: false

  defp valid_value?(:short_string, value),
    do: is_binary(value) and byte_size(String.trim(value)) in 1..500

  defp valid_value?(:slug, value),
    do: is_binary(value) and Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, value)

  defp valid_value?(:positive_integer, value), do: is_integer(value) and value > 0
  defp valid_value?(:non_negative_integer, value), do: is_integer(value) and value >= 0
  defp valid_value?(:positive_number, value), do: is_number(value) and value > 0
  defp valid_value?(:non_negative_number, value), do: is_number(value) and value >= 0
  defp valid_value?(:boolean, value), do: is_boolean(value)

  defp valid_value?(:string_list, value),
    do:
      is_list(value) and length(value) <= 100 and
        Enum.all?(value, &(is_binary(&1) and byte_size(String.trim(&1)) in 1..120))

  defp valid_value?(:duration_range, [minimum, maximum]),
    do: is_integer(minimum) and is_integer(maximum) and minimum >= 0 and maximum >= minimum

  defp valid_value?(:notes, value), do: validate_notes(value) == :ok
  defp valid_value?({:enum, allowed}, value), do: value in allowed

  defp valid_value?({:number_range, minimum, maximum}, value),
    do: is_number(value) and value >= minimum and value <= maximum

  defp valid_value?(_kind, _value), do: false
end
