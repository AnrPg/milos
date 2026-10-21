defmodule MilosTraining.Body.Domain.TrendPolicy do
  @moduledoc """
  How a metric moves over time, in words rather than numbers (ADR-158,
  vision §8.6 "show weight as trend only").

  The series is smoothed with an exponentially weighted moving average, so
  one heavy dinner or a dehydrated morning does not flip the word. The word
  compares the first and last smoothed values relative to the first:

  - under 0.5 % either way: `steady`
  - under 2 %: `slightly_down` / `slightly_up`
  - otherwise: `down` / `up`

  A single measurement has no trend (`nil`).
  """

  @alpha 0.3
  @steady_pct 0.5
  @slight_pct 2.0
  @words ~w(steady slightly_down down slightly_up up)
  @ranges %{"1m" => 30, "3m" => 91, "1y" => 365, "all" => nil}

  def words, do: @words
  def ranges, do: Map.keys(@ranges) |> Enum.sort()
  def alpha, do: @alpha

  @doc "The earliest moment a range covers, given `now` (`nil` for `all`)."
  def since(range, %DateTime{} = now) do
    case Map.fetch(@ranges, range) do
      {:ok, nil} -> {:ok, nil}
      {:ok, days} -> {:ok, DateTime.add(now, -days * 86_400, :second)}
      :error -> {:error, :invalid_range}
    end
  end

  @doc """
  Smoothed values of points `[%{at: DateTime, value: number}]`, oldest
  first; each point gains `:smoothed`.
  """
  def smooth(points) when is_list(points) do
    points
    |> Enum.sort_by(& &1.at, DateTime)
    |> Enum.map_reduce(nil, fn point, previous ->
      smoothed =
        case previous do
          nil -> point.value / 1
          prev -> @alpha * point.value + (1 - @alpha) * prev
        end

      {Map.put(point, :smoothed, Float.round(smoothed, 3)), smoothed}
    end)
    |> elem(0)
  end

  @doc """
  The shape of a series for the trend-only view: the smoothed values
  normalized to 0..1 over the shown range, oldest first, as
  `[%{at: DateTime, y: float}]`. No units, no absolute values, no scale;
  a flat series gives 0.5 throughout.
  """
  def shape(points) when is_list(points) do
    smoothed = smooth(points)

    case Enum.map(smoothed, & &1.smoothed) do
      [] ->
        []

      values ->
        {min, max} = Enum.min_max(values)
        span = max - min

        Enum.map(smoothed, fn point ->
          y = if span == 0, do: 0.5, else: Float.round((point.smoothed - min) / span, 3)
          %{at: point.at, y: y}
        end)
    end
  end

  @doc "The word for a series of points (smoothed first)."
  def word(points) when is_list(points) do
    case smooth(points) do
      [] -> nil
      [_one] -> nil
      smoothed -> classify(hd(smoothed).smoothed, List.last(smoothed).smoothed)
    end
  end

  @doc "The word for a change from `from` to `to`."
  def classify(from, to) when is_number(from) and is_number(to) and from != 0 do
    pct = (to - from) / abs(from) * 100

    cond do
      abs(pct) < @steady_pct -> "steady"
      pct <= -@slight_pct -> "down"
      pct < 0 -> "slightly_down"
      pct >= @slight_pct -> "up"
      true -> "slightly_up"
    end
  end

  def classify(_from, _to), do: nil
end
