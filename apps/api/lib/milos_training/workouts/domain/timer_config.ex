defmodule MilosTraining.Workouts.Domain.TimerConfig do
  @moduledoc """
  Pure validation and normalization for workout section timer configuration.
  """

  @types ~w(
    untimed for_time train_to_exhaustion kcal_target
    emom complex_emom even_odd billat
    amrap edt death_by
    tabata custom_hiit cluster hrr
    ladder_ascending ladder_descending pyramid
    rest
  )

  def normalize(nil), do: {:ok, %{type: "untimed"}}

  def normalize(config) when is_map(config) do
    type = config |> get_value(:type) |> normalize_type()

    with :ok <- validate_type(type),
         :ok <- validate_required_fields(type, config),
         :ok <- validate_optional_fields(type, config) do
      {:ok, build_config(type, config)}
    end
  end

  def normalize(_config), do: {:error, "must be an object"}

  defp validate_type(type) do
    if type in @types, do: :ok, else: {:error, "has unsupported timer type"}
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

  defp required_fields("untimed"), do: []
  defp required_fields("for_time"), do: []
  defp required_fields("train_to_exhaustion"), do: []
  defp required_fields("kcal_target"), do: []
  defp required_fields("emom"), do: [:duration_seconds, :interval_seconds]
  defp required_fields("complex_emom"), do: [:duration_seconds, :interval_seconds]
  defp required_fields("even_odd"), do: [:duration_seconds]
  defp required_fields("billat"), do: [:work_seconds, :rest_seconds, :cycles]
  defp required_fields("amrap"), do: [:duration_seconds]
  defp required_fields("edt"), do: [:duration_seconds]
  defp required_fields("death_by"), do: [:start_reps, :step_reps]
  defp required_fields("tabata"), do: [:work_seconds, :rest_seconds, :rounds]
  defp required_fields("custom_hiit"), do: [:work_seconds, :rest_seconds, :rounds]
  defp required_fields("cluster"), do: [:intra_rest_seconds, :sets]
  defp required_fields("hrr"), do: [:effort_seconds]
  defp required_fields("ladder_ascending"), do: [:start_reps, :step_reps]
  defp required_fields("ladder_descending"), do: [:start_reps, :step_reps, :min_reps]
  defp required_fields("pyramid"), do: [:peak_reps, :step_reps]
  defp required_fields("rest"), do: [:duration_seconds]

  defp optional_fields("for_time"), do: [:time_cap_seconds]
  defp optional_fields("train_to_exhaustion"), do: [:rest_seconds]
  defp optional_fields("kcal_target"), do: [:kcal_target, :time_cap_seconds]
  defp optional_fields("emom"), do: [:scoring_mode, :max_windows]
  defp optional_fields("complex_emom"), do: [:scoring_mode, :amrap_scoring_style]
  defp optional_fields("edt"), do: [:pr_zone_rounds]
  defp optional_fields("death_by"), do: [:ladder_cap]
  defp optional_fields("ladder_ascending"), do: [:ladder_cap]
  defp optional_fields("hrr"), do: [:hr_zone]
  defp optional_fields(_type), do: []

  @valid_scoring_modes ~w(for_time for_quality amrap to_failure)
  @valid_amrap_scoring_styles ~w(grand_total lowest_window)

  defp validate_optional_fields(type, config) when type in ["emom", "complex_emom"] do
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
          else: {:error, "invalid #{field}: #{inspect(value)}"}
    end
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
