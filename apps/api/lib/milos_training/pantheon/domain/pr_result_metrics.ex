defmodule MilosTraining.Pantheon.Domain.PRResultMetrics do
  @moduledoc false

  @integer_fields ~w(reps sets rounds)
  @decimal_fields ~w(load_kg duration_seconds distance_m calories)
  @text_fields ~w(variation)
  @allowed_fields @integer_fields ++ @decimal_fields ++ @text_fields

  def normalize(nil), do: {:ok, %{}}

  def normalize(metrics) when is_map(metrics) do
    with :ok <- validate_allowed_fields(metrics) do
      metrics
      |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, normalized} ->
        field = to_string(key)

        case normalize_field(field, value) do
          {:ok, normalized_value} -> {:cont, {:ok, Map.put(normalized, field, normalized_value)}}
          {:error, reason} -> {:halt, {:error, [supporting_metrics: reason]}}
        end
      end)
    end
  end

  def normalize(_), do: {:error, [supporting_metrics: "must be an object"]}

  defp validate_allowed_fields(metrics) do
    if Enum.all?(Map.keys(metrics), &(to_string(&1) in @allowed_fields)) do
      :ok
    else
      {:error, [supporting_metrics: "contains an unsupported metric"]}
    end
  end

  defp normalize_field(field, value) when field in @integer_fields do
    case numeric(value) do
      {:ok, number} when number < 0 -> {:error, "must be greater than or equal to zero"}
      {:ok, number} when number == trunc(number) -> {:ok, trunc(number)}
      {:ok, _number} -> {:error, "must be a whole number"}
      :error -> {:error, "must be a number"}
    end
  end

  defp normalize_field(field, value) when field in @decimal_fields do
    with {:ok, number} <- numeric(value),
         true <- number >= 0 do
      {:ok, number}
    else
      false -> {:error, "must be greater than or equal to zero"}
      :error -> {:error, "must be a number"}
    end
  end

  defp normalize_field(field, value) when field in @text_fields and is_binary(value) do
    case String.trim(value) do
      "" -> {:error, "must not include blank text"}
      text when byte_size(text) > 120 -> {:error, "must be at most 120 characters"}
      text -> {:ok, text}
    end
  end

  defp normalize_field(field, _value) when field in @text_fields, do: {:error, "must be text"}

  defp numeric(value) when is_integer(value), do: {:ok, value * 1.0}
  defp numeric(value) when is_float(value), do: {:ok, value}

  defp numeric(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp numeric(_value), do: :error
end
