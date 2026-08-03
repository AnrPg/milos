defmodule MilosTraining.Workouts.Domain.TimerConfig do
  @moduledoc """
  Pure validation and normalization for workout section timer configuration.
  """

  alias MilosTraining.Workouts.Domain.WorkoutDsl.Vocabulary

  @valid_scoring_modes ~w(for_time for_quality amrap to_failure)
  @valid_amrap_scoring_styles ~w(grand_total lowest_window)

  def normalize(nil), do: {:ok, %{type: "untimed"}}

  def normalize(config) when is_map(config) do
    type = config |> get_value(:type) |> normalize_type()

    with :ok <- validate_type(type),
         :ok <- validate_required_fields(type, config),
         :ok <- validate_optional_fields(type, config),
         :ok <- validate_registered_fields(type, config),
         :ok <- reject_unknown_fields(type, config) do
      {:ok, build_config(type, config)}
    end
  end

  def normalize(_config), do: {:error, "must be an object"}

  defp validate_type(type) do
    if Vocabulary.valid_section_format?(type),
      do: :ok,
      else: {:error, "has unsupported timer type"}
  end

  defp validate_required_fields(type, config) do
    missing =
      Enum.filter(required_fields(type), fn field ->
        config |> get_value(field) |> blank?()
      end)

    case missing do
      [] ->
        :ok

      fields ->
        {:error,
         "is missing required fields for this timer type: #{Enum.map_join(fields, ", ", &Atom.to_string/1)}"}
    end
  end

  defp required_fields(type), do: Vocabulary.required_timer_fields(type)
  defp optional_fields(type), do: Vocabulary.optional_timer_fields(type)

  defp validate_optional_fields("emom", config) do
    validate_enum_field(config, :scoring_mode, @valid_scoring_modes)
  end

  defp validate_optional_fields("complex_emom", config) do
    with :ok <- validate_enum_field(config, :scoring_mode, @valid_scoring_modes),
         :ok <- validate_enum_field(config, :amrap_scoring_style, @valid_amrap_scoring_styles) do
      :ok
    end
  end

  defp validate_optional_fields(_type, _config), do: :ok

  defp validate_enum_field(config, field, valid_values) do
    case get_value(config, field) do
      nil ->
        :ok

      value ->
        if value in valid_values,
          do: :ok,
          else: {:error, "#{field} must be one of: #{Enum.join(valid_values, ", ")}"}
    end
  end

  defp validate_registered_fields(type, config) do
    Enum.reduce_while(required_fields(type) ++ optional_fields(type), :ok, fn field, :ok ->
      case get_value(config, field) do
        nil ->
          {:cont, :ok}

        value ->
          if valid_registered_value?(field, value),
            do: {:cont, :ok},
            else: {:halt, {:error, "#{field} has an invalid value"}}
      end
    end)
  end

  defp valid_registered_value?(field, value) do
    case Vocabulary.timer_value_kind(field) do
      :duration -> is_integer(value) and value > 0
      :distance -> is_number(value) and value > 0
      :integer -> is_integer(value) and value > 0
      :enum -> value in Vocabulary.timer_enum_values(field)
      :string -> is_binary(value) and String.trim(value) != ""
    end
  end

  defp reject_unknown_fields(type, config) do
    allowed =
      [:type | required_fields(type) ++ optional_fields(type)]
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    unknown =
      config
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&MapSet.member?(allowed, &1))

    if unknown == [],
      do: :ok,
      else: {:error, "contains unsupported fields: #{Enum.map_join(unknown, ", ", &to_string/1)}"}
  end

  defp build_config(type, config) do
    Enum.reduce(required_fields(type) ++ optional_fields(type), %{type: type}, fn key, acc ->
      case get_value(config, key) do
        nil -> acc
        "" -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp get_value(config, key), do: Map.get(config, key) || Map.get(config, Atom.to_string(key))

  defp normalize_type(nil), do: "untimed"
  defp normalize_type(type) when is_atom(type), do: type |> Atom.to_string() |> String.trim()
  defp normalize_type(type), do: type |> to_string() |> String.trim()

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
