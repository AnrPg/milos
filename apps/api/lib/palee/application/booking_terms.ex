defmodule Palee.Application.BookingTerms do
  @moduledoc """
  Booking privileges for a member and class: the member's package terms from
  Finance, falling back to the gym's scheduling defaults (ADR-097).
  """

  alias Palee.{Finance, Scheduling}
  alias Palee.Scheduling.Domain.BookingPolicy

  def for_slot(context, user_id, slot) do
    date = DateTime.to_date(slot.scheduled_at)
    resolve(finance_terms(context, user_id, date), settings(context))
  end

  @doc """
  The moment each slot stops being free to cancel for this member, or nil when
  no cutoff applies. Terms are read once per class date, not once per slot.
  """
  def cancel_free_until(context, user_id, slots) do
    settings = settings(context)

    cutoffs =
      slots
      |> Enum.map(&DateTime.to_date(&1.scheduled_at))
      |> Enum.uniq()
      |> Map.new(fn date ->
        {date, resolve(finance_terms(context, user_id, date), settings).cancellation_cutoff_hours}
      end)

    Enum.map(slots, fn slot ->
      case cutoffs[DateTime.to_date(slot.scheduled_at)] do
        hours when is_integer(hours) -> DateTime.add(slot.scheduled_at, -hours * 3600, :second)
        _ -> nil
      end
    end)
  end

  defp resolve(terms, settings) do
    %{
      booking_window_days:
        BookingPolicy.effective_rule(
          terms[:booking_window_days],
          settings[:default_booking_window_days]
        ),
      cancellation_cutoff_hours:
        BookingPolicy.effective_rule(
          terms[:cancellation_cutoff_hours],
          settings[:default_cancellation_cutoff_hours]
        ),
      waitlist_priority: BookingPolicy.waitlist_priority(terms[:waitlist_priority]),
      no_show_penalty_waived: terms[:no_show_penalty_waived] == true
    }
  end

  defp finance_terms(nil, user_id, date), do: Finance.booking_terms(user_id, date)
  defp finance_terms(context, user_id, date), do: Finance.booking_terms(context, user_id, date)

  defp settings(nil), do: %{}
  defp settings(context), do: Scheduling.get_settings(context)
end
