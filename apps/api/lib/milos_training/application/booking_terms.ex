defmodule MilosTraining.Application.BookingTerms do
  @moduledoc """
  Booking privileges for a member and class: the member's package terms from
  Finance, falling back to the gym's scheduling defaults (ADR-097).
  """

  alias MilosTraining.{Finance, Scheduling}
  alias MilosTraining.Scheduling.Domain.BookingPolicy

  def for_slot(context, user_id, slot) do
    date = DateTime.to_date(slot.scheduled_at)
    terms = finance_terms(context, user_id, date)
    settings = settings(context)

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
