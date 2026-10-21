defmodule MilosTraining.Wellness.Domain.Sleep do
  @moduledoc """
  Ύπνος (ADR-159 §1, vision §7.7): hours and quality 1–5, typed or from a
  device. Any of bedtime and wake time, a duration, or a quality alone is a
  valid night; bedtime and wake time give the duration. A night counts on
  the day you wake up. Naps are their own short entries.
  """

  @behaviour MilosTraining.Wellness.Domain.EntryValue

  alias MilosTraining.Wellness.Domain.EntryValue

  @max_minutes 24 * 60

  @impl true
  def cast(params) do
    with {:ok, value} <-
           EntryValue.collect([
             {"bed_at", EntryValue.instant(params, "bed_at")},
             {"wake_at", EntryValue.instant(params, "wake_at")},
             {"minutes", EntryValue.integer(params, "minutes", 0, @max_minutes)},
             {"quality", EntryValue.integer(params, "quality", 1, 5)},
             {"nap", nap(params)}
           ]),
         {:ok, value} <- span(value) do
      if Map.has_key?(value, "minutes") or Map.has_key?(value, "quality"),
        do: {:ok, Map.put_new(value, "nap", false)},
        else: {:error, %{"minutes" => "give the hours slept or a quality"}}
    end
  end

  @impl true
  def counts_at(%{"wake_at" => wake_at}, _occurred_at) when is_binary(wake_at) do
    {:ok, at, _offset} = DateTime.from_iso8601(wake_at)
    at
  end

  def counts_at(_value, occurred_at), do: occurred_at

  def minutes(%{"minutes" => minutes}) when is_integer(minutes), do: minutes
  def minutes(_value), do: nil

  def nap?(value), do: Map.get(value, "nap", false) == true

  defp nap(params) do
    case EntryValue.get(params, "nap") do
      nil -> {:ok, nil}
      value when is_boolean(value) -> {:ok, value}
      _value -> {:error, %{"nap" => "must be true or false"}}
    end
  end

  # Both ends given: they fix the duration and are stored as ISO text.
  defp span(%{"bed_at" => %DateTime{} = bed, "wake_at" => %DateTime{} = wake} = value) do
    minutes = DateTime.diff(wake, bed, :minute)

    if minutes > 0 and minutes <= @max_minutes do
      {:ok,
       %{value | "bed_at" => iso(bed), "wake_at" => iso(wake)} |> Map.put("minutes", minutes)}
    else
      {:error, %{"wake_at" => "must be after bedtime and within a day"}}
    end
  end

  defp span(value) do
    if Map.has_key?(value, "bed_at") or Map.has_key?(value, "wake_at"),
      do: {:error, %{"wake_at" => "give both bedtime and wake time"}},
      else: {:ok, value}
  end

  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)
end
