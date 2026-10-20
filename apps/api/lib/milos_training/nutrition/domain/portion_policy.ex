defmodule MilosTraining.Nutrition.Domain.PortionPolicy do
  @moduledoc """
  Hand portions of the coach's plan (ADR-159, board 14 Q5): a palm of
  protein, a fist of carbs, a fist of vegetables and a thumb of fat, per
  day, in halves. A coach may write them; otherwise they follow from the
  plan's grams (about 25 g protein a palm, 25 g carbs a fist, 10 g fat a
  thumb), so a plan written in grams still reads without a scale. Vegetables
  have no grams to start from and appear only when the coach sets them.

  The meal slots a plan may name are the vocabulary of Ευεξία's meals.
  """

  @keys ~w(protein carbs veg fat)
  @max_per_day 20
  @grams_per_portion [
    {"protein", :protein_grams, 25},
    {"carbs", :carbs_grams, 25},
    {"fat", :fat_grams, 10}
  ]
  @slots ~w(breakfast morning_snack lunch afternoon_snack dinner evening_snack snack pre_workout post_workout)
  @default_slots ~w(breakfast lunch dinner snack)

  def keys, do: @keys
  def slots, do: @slots
  def default_slots, do: @default_slots

  @doc "Validates coach-written daily portions: `{:ok, map | nil}` or `{:error, message}`."
  def validate(nil), do: {:ok, nil}

  def validate(targets) when is_map(targets) do
    targets
    |> Enum.map(fn {key, amount} -> {to_string(key), amount} end)
    |> Enum.reject(fn {_key, amount} -> is_nil(amount) end)
    |> Enum.reduce_while({:ok, %{}}, fn {key, amount}, {:ok, acc} ->
      if key in @keys and half?(amount, @max_per_day),
        do: {:cont, {:ok, Map.put(acc, key, amount)}},
        else: {:halt, {:error, "use protein, carbs, veg, fat in halves up to #{@max_per_day}"}}
    end)
    |> case do
      {:ok, map} when map == %{} -> {:ok, nil}
      other -> other
    end
  end

  def validate(_targets), do: {:error, "must be an object"}

  @doc "Daily portions from grams, rounded to the nearest half."
  def from_grams(plan) do
    @grams_per_portion
    |> Enum.flat_map(fn {key, field, per} ->
      case Map.get(plan, field) do
        grams when is_integer(grams) and grams > 0 -> [{key, Float.round(grams / per * 2) / 2}]
        _none -> []
      end
    end)
    |> Map.new(fn {key, amount} -> {key, whole(amount)} end)
  end

  @doc "The plan's daily portions: the coach's own, else derived from grams; `nil` if neither."
  def effective(plan) do
    case Map.get(plan, :portion_targets) do
      targets when is_map(targets) and map_size(targets) > 0 ->
        targets

      _none ->
        case from_grams(plan) do
          derived when map_size(derived) > 0 -> derived
          _empty -> nil
        end
    end
  end

  @doc "Sum of portions logged in meal values."
  def logged(meal_values) do
    Enum.reduce(meal_values, Map.new(@keys, &{&1, 0}), fn value, acc ->
      Enum.reduce(Map.get(value, "portions") || %{}, acc, fn {key, amount}, sums ->
        Map.update(sums, key, amount, &whole(&1 + amount))
      end)
    end)
  end

  defp half?(amount, max) when is_integer(amount), do: amount >= 0 and amount <= max

  defp half?(amount, max) when is_float(amount),
    do: amount >= 0 and amount <= max and amount * 2 == Float.round(amount * 2)

  defp half?(_amount, _max), do: false

  defp whole(amount) when is_float(amount) and amount == trunc(amount), do: trunc(amount)
  defp whole(amount), do: amount
end
