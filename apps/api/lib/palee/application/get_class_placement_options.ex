defmodule Palee.Application.GetClassPlacementOptions do
  @moduledoc """
  What staff can choose in «Κλείσιμο ή μετακίνηση μαθήματος» on a member's
  profile (ADR-225): the member's upcoming bookings that can be moved, and
  the upcoming classes of the staff member's branches, each with the reason
  it cannot take the member now (or nil), decided by the same rules as
  `PlaceMemberInClass`. The reasons are the booking error codes, so the
  dialog explains a disabled class in the words it would show for the error.

  Cancelled classes are left out. The member's package is checked the way a
  booking checks it (covers the class, a visit left, not frozen), without
  reserving anything. A class refused only for
  `finance_allowance_exhausted` can still take the member in a move, since
  the move returns the old booking's visit first; the dialog allows it then.
  """

  alias Palee.{Finance, Identity, Organizations, Scheduling}
  alias Palee.Application.PlaceMemberInClass
  alias Palee.Scheduling.Domain.BookingPolicy

  @lookahead_days 30
  @movable_statuses [:pending, :approved]

  def call(%{organization_id: organization_id} = context, user_id)
      when is_binary(organization_id) do
    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found},
         :ok <- PlaceMemberInClass.require_member(context, user.id) do
      now = DateTime.utc_now()

      slots =
        context
        |> Scheduling.get_calendar_week(%{
          start_at: now,
          end_at: DateTime.add(now, @lookahead_days * 86_400, :second),
          class_type_ids: [],
          include_drafts: true
        })
        |> Enum.filter(
          &(DateTime.compare(&1.scheduled_at, now) == :gt and is_nil(Map.get(&1, :cancelled_at)))
        )
        |> then(&Organizations.filter_by_location_scope(context, &1))
        |> Enum.sort_by(& &1.scheduled_at, DateTime)

      {booked, open} = Enum.split_with(slots, &movable_booking(&1, user.id))

      {:ok,
       %{
         timezone: Organizations.organization_timezone(organization_id),
         lookahead_days: @lookahead_days,
         bookings: Enum.map(booked, &booking_option(&1, user.id)),
         classes: class_options(context, open, user, now)
       }}
    end
  end

  def call(_context, _user_id), do: {:error, :organization_context_required}

  defp movable_booking(slot, user_id) do
    Enum.find(slot.bookings, fn booking ->
      booking.user_id == user_id and booking.status in @movable_statuses and
        Map.get(booking, :kind, "member") == "member"
    end)
  end

  defp booking_option(slot, user_id) do
    booking = movable_booking(slot, user_id)

    %{
      booking_id: booking.id,
      slot_id: slot.id,
      name: slot.name,
      scheduled_at: slot.scheduled_at,
      status: booking.status
    }
  end

  defp class_options(_context, [], _user, _now), do: []

  defp class_options(context, slots, user, now) do
    {bookable, closed} =
      slots
      |> Enum.map(&{&1, policy_reason(&1, user.id, now)})
      |> Enum.split_with(fn {_slot, reason} -> is_nil(reason) end)

    requests =
      Enum.map(bookable, fn {slot, nil} ->
        slot
        |> BookingPolicy.entitlement_request()
        |> Map.merge(%{
          actor_role: user.role,
          starts_at: slot.scheduled_at,
          location_id: Map.get(slot, :location_id)
        })
      end)

    package_reasons =
      context
      |> Finance.check_entitlements(user.id, requests)
      |> Enum.map(fn
        :ok -> nil
        {:error, reason} -> Atom.to_string(reason)
      end)

    checked =
      Enum.zip_with(bookable, package_reasons, fn {slot, nil}, reason -> {slot, reason} end)

    (checked ++ closed)
    |> Enum.sort_by(fn {slot, _reason} -> slot.scheduled_at end, DateTime)
    |> Enum.map(fn {slot, reason} ->
      %{
        slot_id: slot.id,
        name: slot.name,
        scheduled_at: slot.scheduled_at,
        duration_minutes: slot.duration_minutes,
        capacity: slot.capacity,
        spots_remaining: max(slot.spots_remaining || 0, 0),
        blocked_reason: reason
      }
    end)
  end

  defp policy_reason(slot, user_id, now) do
    case BookingPolicy.can_book?(slot, user_id: user_id, now: now) do
      :ok -> nil
      {:error, reason} -> Atom.to_string(reason)
    end
  end
end
