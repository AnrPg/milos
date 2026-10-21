defmodule Palee.Application.DailyStats do
  @moduledoc """
  Πρόοδος › resting heart rate (ADR-161, board 16 Q4 A) and steps (ADR-172):
  the member's own daily stats from a connected device, one point per day
  and source, read in their personal session (owner row security). An
  indicator to look at, never a judgement: no grades, no targets.
  """

  alias Palee.Devices

  @metrics ~w(resting_hr steps)
  @fields %{"resting_hr" => :resting_heart_rate, "steps" => :steps}
  @ranges %{"1m" => 30, "3m" => 90, "1y" => 365}
  @default_range "3m"

  def metrics, do: @metrics
  def ranges, do: Map.keys(@ranges) |> Enum.sort()
  def default_range, do: @default_range

  @doc """
  `%{metric, range, from, to, points: [%{on, value, source}], latest, average,
  sources}` for `metric` over `range` ending `today`. `latest` and `average`
  are nil when there is nothing, so the client shows no card.
  """
  def series(%{user_id: user_id} = context, params, today \\ Date.utc_today()) do
    with {:ok, metric} <- metric(param(params, "metric")),
         {:ok, range, days} <- range(param(params, "range")) do
      from = Date.add(today, -(days - 1))

      field = Map.fetch!(@fields, metric)

      points =
        context
        |> Devices.with_context(fn -> Devices.list_daily_stats(user_id, from, today) end)
        |> Enum.filter(&is_integer(Map.get(&1, field)))
        |> Enum.map(&%{on: &1.on, value: Map.get(&1, field), source: &1.source})

      {:ok,
       %{
         metric: metric,
         range: range,
         from: from,
         to: today,
         points: points,
         latest: List.last(points),
         average: average(points),
         sources: points |> Enum.map(& &1.source) |> Enum.uniq()
       }}
    end
  end

  defp average([]), do: nil

  defp average(points),
    do: round(Enum.sum(Enum.map(points, & &1.value)) / length(points))

  defp metric(nil), do: {:ok, "resting_hr"}
  defp metric(metric) when metric in @metrics, do: {:ok, metric}
  defp metric(metric) when is_atom(metric), do: metric(Atom.to_string(metric))
  defp metric(_metric), do: {:error, :invalid_daily_stat_metric}

  defp range(nil), do: range(@default_range)

  defp range(range) when is_map_key(@ranges, range),
    do: {:ok, range, Map.fetch!(@ranges, range)}

  defp range(range) when is_atom(range), do: range(Atom.to_string(range))
  defp range(_range), do: {:error, :invalid_range}

  defp param(params, key) when is_map(params) do
    case Map.fetch(params, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(params, fn {k, v} -> if is_atom(k) and Atom.to_string(k) == key, do: v end)
    end
  end
end
