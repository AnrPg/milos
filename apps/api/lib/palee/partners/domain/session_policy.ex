defmodule Palee.Partners.Domain.SessionPolicy do
  @moduledoc """
  «Κλείστε μαζί» (ADR-169 §8). Pure.

  The gym's classes of the next 7 days that still take people, or that one
  of the two already booked: those either of them booked first, then those
  in times both chose, then the soonest. For each class only whether these
  two are booked, never who else is. At most six.
  """

  @window_days 7
  @max 6
  @booked ~w(pending approved)a

  def window_days, do: @window_days

  def window(now), do: {now, DateTime.add(now, @window_days * 86_400, :second)}

  @doc "The Partners time a class falls in, in the gym's zone."
  def period(%DateTime{} = at, timezone) do
    local =
      case DateTime.shift_zone(at, timezone || "Etc/UTC") do
        {:ok, local} -> local
        _error -> at
      end

    if Date.day_of_week(local) in [6, 7] do
      "weekend"
    else
      cond do
        local.hour < 9 -> "early"
        local.hour < 15 -> "midday"
        local.hour < 18 -> "afternoon"
        true -> "evening"
      end
    end
  end

  @doc "Ranked suggestions: `[%{slot, booked: [user_ids], shared_time: bool}]`."
  def suggestions(slots, pair_ids, shared_times, timezone, now) do
    slots
    |> Enum.filter(&(DateTime.compare(&1.scheduled_at, now) == :gt))
    |> Enum.map(fn slot ->
      booked =
        slot
        |> Map.get(:bookings, [])
        |> Enum.filter(&(&1.user_id in pair_ids and status(&1) in @booked))
        |> Enum.map(& &1.user_id)
        |> Enum.uniq()

      %{
        slot: slot,
        booked: booked,
        shared_time: period(slot.scheduled_at, timezone) in shared_times
      }
    end)
    |> Enum.filter(&(&1.booked != [] or Map.get(&1.slot, :spots_remaining, 0) > 0))
    |> Enum.sort_by(
      &{-length(&1.booked), not &1.shared_time, DateTime.to_unix(&1.slot.scheduled_at)}
    )
    |> Enum.take(@max)
  end

  defp status(%{status: status}) when is_atom(status), do: status
  defp status(%{status: status}) when is_binary(status), do: String.to_existing_atom(status)
  defp status(_booking), do: nil
end
