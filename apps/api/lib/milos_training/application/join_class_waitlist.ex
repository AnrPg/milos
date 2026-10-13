defmodule MilosTraining.Application.JoinClassWaitlist do
  @moduledoc """
  Adds a member to a full class's waitlist (ADR-097). No visit is reserved
  until the entry is promoted; the member's package must already allow the
  class so ineligible members are told immediately.
  """

  alias MilosTraining.Application.{
    AuthorizeFinanceEntitlement,
    BookingTerms,
    ScheduleRealtime
  }

  alias MilosTraining.Scheduling
  alias MilosTraining.Scheduling.Domain.BookingPolicy

  def call(context, %{id: user_id} = actor, slot_id) do
    now = DateTime.utc_now()

    with %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
         :ok <- BookingPolicy.can_join_waitlist?(slot, user_id: user_id, now: now),
         terms = BookingTerms.for_slot(context, user_id, slot),
         :ok <-
           BookingPolicy.booking_window_open?(slot.scheduled_at, now, terms.booking_window_days),
         request = BookingPolicy.entitlement_request(slot),
         :ok <- eligible(context, actor, slot, request),
         {:ok, entry} <-
           Scheduling.join_waitlist(context, user_id, slot.id, %{
             waitlist_priority: terms.waitlist_priority,
             entitlement_allowance: BookingPolicy.booking_allowance(request)
           }) do
      ScheduleRealtime.broadcast("booking_waitlisted", entry)
      {:ok, entry}
    end
  end

  # Checks access and scope without reserving; quotas are checked at promotion.
  defp eligible(context, actor, slot, request) do
    check =
      request
      |> Map.drop([:allowance, :quantity])
      |> Map.merge(%{starts_at: slot.scheduled_at, location_id: Map.get(slot, :location_id)})

    case AuthorizeFinanceEntitlement.call(context, actor, check) do
      :ok -> :ok
      {:ok, _decision} -> :ok
      error -> error
    end
  end
end
