defmodule MilosTraining.Facility.Domain.PlacePolicy do
  @moduledoc """
  Pure rules for where a location is and when it is open (ADR-141):
  coordinates, neighbourhood, weekly opening hours and accessibility.
  """

  @accessibility ~w(step_free accessible_toilet parking changing_room showers women_only_area)
  @time ~r/^([01]\d|2[0-3]):[0-5]\d$/

  @doc "Accessibility features a location can declare."
  def accessibility_features, do: @accessibility

  @doc "Coordinates are kept to 6 decimals (about 0.1 m)."
  def round_coordinate(nil), do: nil
  def round_coordinate(value) when is_number(value), do: Float.round(value * 1.0, 6)

  @doc "A neighbourhood or city name: trimmed, inner whitespace collapsed, blank → nil."
  def normalize_name(nil), do: nil

  def normalize_name(value) when is_binary(value) do
    case value |> String.split() |> Enum.join(" ") do
      "" -> nil
      name -> name
    end
  end

  def normalize_country_code(nil), do: nil

  def normalize_country_code(code) when is_binary(code) do
    case String.upcase(String.trim(code)) do
      "" -> nil
      code -> code
    end
  end

  def valid_country_code?(code), do: is_binary(code) and code =~ ~r/^[A-Z]{2}$/

  @doc """
  Validates weekly opening hours: a list of
  `%{"weekday" => 1..7, "opens" => "HH:MM", "closes" => "HH:MM"}` (ISO
  weekdays, Monday = 1). A span may cross midnight (`closes` before `opens`).
  Spans of one day must not overlap. Returns the spans sorted, or errors.
  """
  def normalize_opening_hours(spans) when is_list(spans) do
    spans
    |> Enum.reduce_while({:ok, []}, fn span, {:ok, acc} ->
      case normalize_span(span) do
        {:ok, span} -> {:cont, {:ok, [span | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, spans} ->
        spans = Enum.sort_by(spans, &{&1["weekday"], &1["opens"]})
        if overlapping?(spans), do: {:error, :overlapping_spans}, else: {:ok, spans}

      error ->
        error
    end
  end

  def normalize_opening_hours(_spans), do: {:error, :invalid_opening_hours}

  defp normalize_span(%{} = span) do
    span = Map.new(span, fn {key, value} -> {to_string(key), value} end)

    with weekday when weekday in 1..7 <- span["weekday"],
         opens when is_binary(opens) <- span["opens"],
         closes when is_binary(closes) <- span["closes"],
         true <- opens =~ @time and closes =~ @time and opens != closes do
      {:ok, %{"weekday" => weekday, "opens" => opens, "closes" => closes}}
    else
      _invalid -> {:error, :invalid_opening_hours}
    end
  end

  defp normalize_span(_span), do: {:error, :invalid_opening_hours}

  # Spans of the same weekday overlap when one opens before the previous
  # closes; a span crossing midnight ends the day.
  defp overlapping?(spans) do
    spans
    |> Enum.group_by(& &1["weekday"])
    |> Enum.any?(fn {_weekday, day} ->
      day
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.any?(fn [first, second] ->
        crosses_midnight?(first) or second["opens"] < first["closes"]
      end)
    end)
  end

  defp crosses_midnight?(span), do: span["closes"] < span["opens"]
end
