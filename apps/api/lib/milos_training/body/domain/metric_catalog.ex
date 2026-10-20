defmodule MilosTraining.Body.Domain.MetricCatalog do
  @moduledoc """
  The body metrics a snapshot may hold (ADR-158), their canonical SI unit,
  the range a value must fall in and how they convert for people who use
  imperial units.

  Values are stored in SI (kg, cm, %) with three decimals, so a value typed
  in pounds or inches shows back exactly as typed (to one decimal). Ranges
  are in SI and generous: they catch typos (a weight of 7240), not bodies.
  """

  @lb_per_kg 2.204_622_621_85
  @cm_per_in 2.54

  # key => {kind, min, max} with min/max in SI units
  @metrics [
    {"weight", :mass, 20.0, 400.0},
    {"body_fat", :percent, 2.0, 75.0},
    {"waist", :length, 40.0, 250.0},
    {"hips", :length, 50.0, 250.0},
    {"chest", :length, 50.0, 250.0},
    {"arm", :length, 10.0, 80.0},
    {"thigh", :length, 20.0, 120.0},
    {"neck", :length, 20.0, 70.0},
    {"calf", :length, 15.0, 80.0},
    {"arm_left", :length, 10.0, 80.0},
    {"arm_right", :length, 10.0, 80.0},
    {"thigh_left", :length, 20.0, 120.0},
    {"thigh_right", :length, 20.0, 120.0}
  ]

  @by_key Map.new(@metrics, fn {key, kind, min, max} ->
            {key, %{key: key, kind: kind, min: min, max: max}}
          end)

  @keys Enum.map(@metrics, &elem(&1, 0))
  @unit_systems ~w(metric imperial)
  # Weight and body fat are the numbers a person may choose not to see.
  @sensitive ~w(weight body_fat)

  def keys, do: @keys
  def unit_systems, do: @unit_systems
  def sensitive, do: @sensitive
  def sensitive?(key), do: key in @sensitive
  def known?(key), do: is_map_key(@by_key, key)

  @doc "The unit a metric shows in, in a unit system."
  def unit(key, units) do
    case {Map.fetch!(@by_key, key).kind, units} do
      {:mass, "imperial"} -> "lb"
      {:mass, _metric} -> "kg"
      {:length, "imperial"} -> "in"
      {:length, _metric} -> "cm"
      {:percent, _any} -> "%"
    end
  end

  @doc "The catalog as a client shows it: key, unit and range in `units`."
  def catalog(units) do
    Enum.map(@keys, fn key ->
      metric = Map.fetch!(@by_key, key)

      %{
        key: key,
        unit: unit(key, units),
        min: present(key, metric.min, units),
        max: present(key, metric.max, units),
        sensitive: sensitive?(key)
      }
    end)
  end

  @doc "A value in `units` converted to its canonical SI value."
  def to_canonical(key, value, units) when is_number(value) do
    si =
      case {Map.fetch!(@by_key, key).kind, units} do
        {:mass, "imperial"} -> value / @lb_per_kg
        {:length, "imperial"} -> value * @cm_per_in
        _same -> value / 1
      end

    Float.round(si, 3)
  end

  @doc "A canonical SI value as shown in `units`, to one decimal."
  def present(key, value, units) when is_number(value) do
    shown =
      case {Map.fetch!(@by_key, key).kind, units} do
        {:mass, "imperial"} -> value * @lb_per_kg
        {:length, "imperial"} -> value / @cm_per_in
        _same -> value / 1
      end

    Float.round(shown, 1)
  end

  @doc "Every value of a canonical metrics map as shown in `units`."
  def present_all(metrics, units) when is_map(metrics),
    do: Map.new(metrics, fn {key, value} -> {key, present(key, value, units)} end)

  @doc """
  Validates metrics typed in `units` and returns them in canonical SI.
  A `nil` value means "remove this metric" and is kept as `nil` for the
  caller to apply. Errors: `{:error, :invalid_metric, %{metric, reason}}`
  with reason `unknown`, `not_a_number` or `out_of_range` (and the range in
  `units`).
  """
  def validate(metrics, units) when is_map(metrics) and units in @unit_systems do
    Enum.reduce_while(metrics, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      key = to_string(key)

      case validate_one(key, value, units) do
        {:ok, canonical} -> {:cont, {:ok, Map.put(acc, key, canonical)}}
        {:error, details} -> {:halt, {:error, :invalid_metric, details}}
      end
    end)
  end

  def validate(_metrics, _units), do: {:error, :invalid_metric, %{reason: "not_an_object"}}

  defp validate_one(key, _value, _units) when not is_map_key(@by_key, key),
    do: {:error, %{metric: key, reason: "unknown"}}

  defp validate_one(_key, nil, _units), do: {:ok, nil}

  defp validate_one(key, value, units) when is_number(value) do
    metric = Map.fetch!(@by_key, key)
    canonical = to_canonical(key, value, units)

    if canonical >= metric.min and canonical <= metric.max do
      {:ok, canonical}
    else
      {:error,
       %{
         metric: key,
         reason: "out_of_range",
         min: present(key, metric.min, units),
         max: present(key, metric.max, units),
         unit: unit(key, units)
       }}
    end
  end

  defp validate_one(key, value, units) when is_binary(value) do
    case Float.parse(String.replace(String.trim(value), ",", ".")) do
      {number, ""} -> validate_one(key, number, units)
      _other -> {:error, %{metric: key, reason: "not_a_number"}}
    end
  end

  defp validate_one(key, _value, _units), do: {:error, %{metric: key, reason: "not_a_number"}}

  @doc "Applies validated changes to stored metrics: `nil` removes a metric."
  def merge(stored, changes) when is_map(stored) and is_map(changes) do
    Enum.reduce(changes, stored, fn
      {key, nil}, acc -> Map.delete(acc, key)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  @doc "Stored metrics with only known keys and numeric values (rows read back as JSON)."
  def clean(metrics) when is_map(metrics) do
    for {key, value} <- metrics, known?(key), is_number(value), into: %{}, do: {key, value / 1}
  end

  def clean(_metrics), do: %{}
end
