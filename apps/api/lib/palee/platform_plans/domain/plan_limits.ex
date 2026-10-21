defmodule Palee.PlatformPlans.Domain.PlanLimits do
  @moduledoc """
  What a platform plan allows (ADR-170). A limit is a positive integer; a key
  that is absent means unlimited. The keys are a closed list so a typo in the
  platform console can never silently lift a limit.

  - `staff_seats`: accounts holding an owner, admin or staff role, plus
    staff invitations not yet redeemed. A hard limit: a new seat is refused.
  - `active_clients`: active members and athletes. A soft limit: usage and a
    warning only, a client is never turned away for the coach's plan.
  """

  @keys ~w(staff_seats active_clients)
  @hard ~w(staff_seats)
  @max 1_000_000
  @near_ratio 0.9

  def keys, do: @keys
  def hard?(key), do: key in @hard

  @doc "Validates and normalizes a limits map (string keys, integer values)."
  def parse(limits) when is_map(limits) do
    Enum.reduce_while(limits, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      key = to_string(key)

      cond do
        key not in @keys ->
          {:halt, {:error, :invalid_plan_limits}}

        is_nil(value) ->
          {:cont, {:ok, acc}}

        is_integer(value) and value >= 1 and value <= @max ->
          {:cont, {:ok, Map.put(acc, key, value)}}

        true ->
          {:halt, {:error, :invalid_plan_limits}}
      end
    end)
  end

  def parse(_limits), do: {:error, :invalid_plan_limits}

  @doc "The limit for `key`, or `:unlimited`."
  def limit(limits, key) when is_map(limits) do
    case Map.get(limits, key) do
      value when is_integer(value) -> value
      _absent -> :unlimited
    end
  end

  def limit(_limits, _key), do: :unlimited

  @doc """
  Whether `adding` more of `key` fits next to `used`. Only hard limits refuse;
  a soft limit always answers `:ok`.
  """
  def check(limits, key, used, adding \\ 1) when is_integer(used) and is_integer(adding) do
    case limit(limits, key) do
      :unlimited ->
        :ok

      max ->
        if not hard?(key) or used + adding <= max, do: :ok, else: {:error, :plan_limit_reached}
    end
  end

  @doc "One row per key for the plan card: used, limit and a state."
  def usage(limits, used_by_key) when is_map(used_by_key) do
    Enum.map(@keys, fn key ->
      used = Map.get(used_by_key, key, 0)
      max = limit(limits, key)
      %{key: key, used: used, limit: max, hard: hard?(key), state: state(used, max)}
    end)
  end

  defp state(_used, :unlimited), do: :ok
  defp state(used, max) when used > max, do: :over
  defp state(used, max) when used == max, do: :reached
  defp state(used, max) when used >= max * @near_ratio, do: :near
  defp state(_used, _max), do: :ok
end
