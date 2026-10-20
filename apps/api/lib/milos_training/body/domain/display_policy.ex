defmodule MilosTraining.Body.Domain.DisplayPolicy do
  @moduledoc """
  What a body reading may show (ADR-158, vision §8.6). Weight and body fat
  are always stored, but the person chooses how they show:

  - `number`: the values themselves;
  - `trend`: never the numbers, only the direction in words;
  - `hidden`: nothing at all, not even the direction.

  Every other metric (circumferences) always shows. The same choice applies
  when a coach reads a shared snapshot: a coach never sees a number the
  person chose not to see. Every response that carries body numbers goes
  through this module.
  """

  alias MilosTraining.Body.Domain.{MetricCatalog, TrendPolicy}

  @modes ~w(number trend hidden)

  def modes, do: @modes

  @doc "How one metric shows under `weight_display`."
  def mode(key, weight_display) do
    if MetricCatalog.sensitive?(key), do: weight_display, else: "number"
  end

  @doc """
  Canonical metrics as they may be shown: `%{metrics: %{key => value in
  units}, withheld: [key]}`. A withheld metric exists but its number does
  not leave the server.
  """
  def metrics(metrics, %{weight_display: display, units: units}) when is_map(metrics) do
    {shown, withheld} =
      metrics
      |> MetricCatalog.clean()
      |> Enum.split_with(fn {key, _value} -> mode(key, display) == "number" end)

    withheld_keys =
      for {key, _value} <- withheld, mode(key, display) == "trend", do: key

    %{
      metrics: shown |> Map.new() |> MetricCatalog.present_all(units),
      withheld: Enum.sort(withheld_keys)
    }
  end

  @doc """
  A metric's series as it may be shown. `points` are
  `[%{at: DateTime, value: canonical}]`. Returns `%{display, points, trend}`:
  points with `value` and `smoothed` in units when numbers may show, no
  points (only the trend word) under `trend`, and neither under `hidden`.
  """
  def series(key, points, %{weight_display: display, units: units}) do
    case mode(key, display) do
      "number" ->
        smoothed = TrendPolicy.smooth(points)

        %{
          display: "number",
          trend: TrendPolicy.word(points),
          points:
            Enum.map(smoothed, fn point ->
              %{
                at: point.at,
                value: MetricCatalog.present(key, point.value, units),
                smoothed: MetricCatalog.present(key, point.smoothed, units)
              }
            end)
        }

      "trend" ->
        %{display: "trend", trend: TrendPolicy.word(points), points: []}

      "hidden" ->
        %{display: "hidden", trend: nil, points: []}
    end
  end

  @doc """
  Changes between two canonical metric maps, for metrics both hold:
  `[%{metric, delta, direction}]`. Under `trend` the delta is `nil` and only
  the direction shows; under `hidden` the metric is left out.
  """
  def deltas(from, to, %{weight_display: display, units: units}) do
    from = MetricCatalog.clean(from)
    to = MetricCatalog.clean(to)

    MetricCatalog.keys()
    |> Enum.filter(&(Map.has_key?(from, &1) and Map.has_key?(to, &1)))
    |> Enum.flat_map(fn key ->
      direction = TrendPolicy.classify(from[key], to[key])

      case mode(key, display) do
        "number" ->
          delta =
            Float.round(
              MetricCatalog.present(key, to[key], units) -
                MetricCatalog.present(key, from[key], units),
              1
            )

          [%{metric: key, delta: delta, direction: direction}]

        "trend" ->
          [%{metric: key, delta: nil, direction: direction}]

        "hidden" ->
          []
      end
    end)
  end
end
