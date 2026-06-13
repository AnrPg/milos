defmodule MilosTraining.Gamification.Domain.ChallengeCriteria do
  @valid_types ~w(workout_count workout_type_count pr_count custom)
  @training_types ~w(crossfit strength gymnastics aerobics flexibility recovery)
  @rule_conditions ~w(workout_type scale_level pr_beaten weekly_consistency rare_workout_type team_workout_streak)

  def normalize(criteria_type, criteria_value) do
    type = normalize_type(criteria_type)
    value = criteria_value || %{}

    with :ok <- validate_type(type),
         {:ok, normalized_count} <- fetch_positive_integer(value, "count"),
         {:ok, normalized_value} <- normalize_value(type, normalized_count, value) do
      {:ok, %{criteria_type: type, criteria_value: normalized_value}}
    end
  end

  def target(%{criteria_value: criteria_value}) do
    case fetch_positive_integer(criteria_value || %{}, "count") do
      {:ok, count} -> count
      :error -> 1
    end
  end

  def has_rules?(criteria_value) when is_map(criteria_value) do
    rules = Map.get(criteria_value, "rules") || Map.get(criteria_value, :rules)
    is_list(rules) and rules != []
  end

  def has_rules?(_), do: false

  def rules(criteria_value) when is_map(criteria_value) do
    Map.get(criteria_value, "rules") || Map.get(criteria_value, :rules) || []
  end

  def rules(_), do: []

  def increment_per_completion(%{criteria_value: criteria_value}) do
    case fetch_positive_integer(criteria_value || %{}, "increment_per_completion") do
      {:ok, increment} -> increment
      :error -> 1
    end
  end

  def increment_label(%{criteria_value: criteria_value}) do
    Map.get(criteria_value || %{}, "increment_label") ||
      Map.get(criteria_value || %{}, :increment_label)
  end

  defp validate_type(type) when type in @valid_types, do: :ok
  defp validate_type(_type), do: {:error, [criteria_type: "is invalid"]}

  defp normalize_value("workout_count", count, _value), do: {:ok, %{"count" => count}}
  defp normalize_value("pr_count", count, _value), do: {:ok, %{"count" => count}}

  defp normalize_value("workout_type_count", count, value) do
    type_filter = Map.get(value, "type_filter") || Map.get(value, :type_filter)

    if type_filter in @training_types do
      {:ok, %{"count" => count, "type_filter" => type_filter}}
    else
      {:error, [criteria_value: "type_filter must be a valid training type"]}
    end
  end

  defp normalize_value("custom", count, value) do
    rules = Map.get(value, "rules") || Map.get(value, :rules)

    cond do
      is_list(rules) and rules != [] ->
        case validate_rules(rules) do
          :ok -> {:ok, %{"count" => count, "rules" => normalize_rules(rules)}}
          {:error, reason} -> {:error, reason}
        end

      true ->
        case fetch_positive_integer(value, "increment_per_completion") do
          {:ok, increment} ->
            label = Map.get(value, "increment_label") || Map.get(value, :increment_label)

            normalized = %{"count" => count, "increment_per_completion" => increment}

            normalized =
              if is_binary(label) and String.length(label) <= 160,
                do: Map.put(normalized, "increment_label", label),
                else: normalized

            {:ok, normalized}

          :error ->
            {:error, [criteria_value: "must have increment_per_completion or rules"]}
        end
    end
  end

  defp validate_rules(rules) do
    Enum.reduce_while(rules, :ok, fn rule, :ok ->
      case validate_rule(rule) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_rule(%{"condition" => condition} = rule) when condition in @rule_conditions do
    case fetch_positive_integer(rule, "points") do
      {:ok, _} -> :ok
      :error -> {:error, [criteria_value: "each rule must have points >= 1"]}
    end
  end

  defp validate_rule(_),
    do:
      {:error,
       [criteria_value: "rule condition must be one of: #{Enum.join(@rule_conditions, ", ")}"]}

  defp normalize_rules(rules) do
    Enum.map(rules, fn rule ->
      base = %{
        "condition" => rule["condition"] || to_string(rule[:condition] || ""),
        "points" => cast_integer(rule["points"] || rule[:points])
      }

      rule
      |> Map.take(~w(type slug threshold threshold_pct min_count label))
      |> Map.merge(base)
    end)
  end

  defp normalize_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_type(type) when is_binary(type), do: type
  defp normalize_type(_type), do: nil

  defp fetch_positive_integer(map, key) do
    value = Map.get(map, key) || Map.get(map, String.to_atom(key))

    case cast_integer(value) do
      int when is_integer(int) and int > 0 -> {:ok, int}
      _other -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp cast_integer(value) when is_integer(value), do: value
  defp cast_integer(value) when is_float(value) and trunc(value) == value, do: trunc(value)

  defp cast_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> :error
    end
  end

  defp cast_integer(_value), do: :error
end
