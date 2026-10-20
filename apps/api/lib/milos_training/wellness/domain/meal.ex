defmodule MilosTraining.Wellness.Domain.Meal do
  @moduledoc """
  Γεύμα (ADR-159 §1, vision §7.7, §8.6): a meal, optionally in a slot, «εντός»
  or «εκτός πλάνου», with an optional photo and line of text. Optional hand
  portions (palm, fist, cupped hand, thumb) let a coach's plan be followed
  without weighing food. No calories, ever.
  """

  @behaviour MilosTraining.Wellness.Domain.EntryValue

  alias MilosTraining.Wellness.Domain.EntryValue

  @slots ~w(breakfast lunch dinner snack)
  @main_slots ~w(breakfast lunch dinner)
  @plan_fits ~w(in_plan off_plan)
  @portions ~w(protein carbs veg fat)
  @max_portions 10

  def slots, do: @slots
  def main_slots, do: @main_slots
  def plan_fits, do: @plan_fits
  def portion_keys, do: @portions

  @impl true
  def cast(params) do
    EntryValue.collect([
      {"slot", EntryValue.one_of(params, "slot", @slots)},
      {"plan_fit", EntryValue.one_of(params, "plan_fit", @plan_fits)},
      {"note", EntryValue.text(params, "note", 280)},
      {"media_id", cast_media_id(params)},
      {"portions", portions(params)},
      {"hunger_before", EntryValue.integer(params, "hunger_before", 1, 5)},
      {"fullness_after", EntryValue.integer(params, "fullness_after", 1, 5)}
    ])
  end

  @impl true
  def counts_at(_value, occurred_at), do: occurred_at

  def media_id(%{"media_id" => id}) when is_binary(id), do: id
  def media_id(_value), do: nil

  defp cast_media_id(params) do
    case EntryValue.get(params, "media_id") do
      nil ->
        {:ok, nil}

      value ->
        case Ecto.UUID.cast(value) do
          {:ok, id} -> {:ok, id}
          :error -> {:error, %{"media_id" => "is not a media id"}}
        end
    end
  end

  # Half portions are allowed («μισή γροθιά»); stored as numbers.
  defp portions(params) do
    case EntryValue.get(params, "portions") do
      nil ->
        {:ok, nil}

      portions when is_map(portions) ->
        portions
        |> Enum.map(fn {key, amount} -> {to_string(key), amount} end)
        |> Enum.reduce_while({:ok, %{}}, fn {key, amount}, {:ok, acc} ->
          if key in @portions and portion?(amount),
            do: {:cont, {:ok, Map.put(acc, key, amount)}},
            else:
              {:halt,
               {:error,
                %{"portions" => "use protein, carbs, veg, fat in halves up to #{@max_portions}"}}}
        end)
        |> case do
          {:ok, map} when map == %{} -> {:ok, nil}
          other -> other
        end

      _other ->
        {:error, %{"portions" => "must be an object"}}
    end
  end

  defp portion?(amount) when is_integer(amount), do: amount >= 0 and amount <= @max_portions

  defp portion?(amount) when is_float(amount),
    do: amount >= 0 and amount <= @max_portions and amount * 2 == Float.round(amount * 2)

  defp portion?(_amount), do: false
end
