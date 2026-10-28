defmodule Palee.Application.PlaceMemberInClass do
  @moduledoc """
  Lets staff book a member into a scheduled class from the member's profile,
  optionally moving them out of one of their upcoming bookings (ADR-225).

  The new booking passes the regular checks (class open and published, a free
  place, not in the past, the member's package covers it and has a visit
  left) but is approved at once and ignores the member's booking window,
  because staff place the member themselves.

  A move is one transaction: the old booking is withdrawn and its visit
  returned first, so a member with one visit left can still be moved, and
  the new booking is written next; if it is refused, the old booking stays
  as it was. A move is never a late cancellation, since the member did not
  cancel. Notifications, realtime updates and the waitlist promotion of the
  freed place run only after the transaction commits.
  """

  alias Palee.Application.{ClassLocation, SubmitBooking, WithdrawBooking}
  alias Palee.{Identity, Organizations, Scheduling}

  def call(context, user_id, params) do
    slot_id = value(params, :slot_id)
    from_booking_id = value(params, :from_booking_id)

    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found},
         # ADR-186: staff place members in classes of their own branches.
         :ok <- ClassLocation.authorize_class(context, slot_id),
         :ok <- require_member(context, user.id),
         {:ok, previous} <- previous_booking(context, user.id, from_booking_id),
         :ok <- authorize_previous(context, previous),
         {:ok, written} <- write(context, user, slot_id, previous) do
      announce(context, written)
      {:ok, %{booking: written.booking, previous_booking_id: previous && previous.id}}
    end
  end

  defp write(context, user, slot_id, previous) do
    now = DateTime.utc_now()

    context
    |> Scheduling.transaction(fn ->
      with {:ok, withdrawn} <- withdraw_previous(context, user.id, previous),
           {:ok, slot, booking} <- book(context, user, slot_id, now) do
        {:ok, %{slot: slot, booking: booking, withdrawn: withdrawn, now: now}}
      end
    end)
    |> case do
      {:ok, written} -> {:ok, written}
      {:error, {:with_details, reason, details}} -> {:error, reason, details}
      {:error, reason} -> {:error, reason}
    end
  end

  defp book(context, user, slot_id, now) do
    case SubmitBooking.write(context, user, slot_id,
           approved: true,
           booking_window: false,
           now: now
         ) do
      {:ok, slot, booking} -> {:ok, slot, booking}
      {:error, reason, details} -> {:error, {:with_details, reason, details}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp withdraw_previous(_context, _user_id, nil), do: {:ok, nil}

  defp withdraw_previous(context, user_id, previous) do
    with {:ok, booking, withdrawn, late?} <-
           WithdrawBooking.write(context, user_id, previous.id, late_cancellation: false) do
      {:ok, {booking, withdrawn, late?}}
    end
  end

  defp announce(context, %{slot: slot, booking: booking, withdrawn: withdrawn, now: now}) do
    case withdrawn do
      nil ->
        :ok

      {old, withdrawn_booking, late?} ->
        WithdrawBooking.announce(context, old, withdrawn_booking, late?, :staff)
    end

    SubmitBooking.announce(context, slot, booking, now)
  end

  @doc "Only active members of the box are placed in classes (athletes and coaching clients are not)."
  def require_member(%{organization_id: organization_id}, user_id) do
    member? =
      user_id
      |> Organizations.list_memberships()
      |> Enum.any?(fn %{membership: membership, organization: organization} ->
        organization.id == organization_id and membership.status == :active and
          membership.role == :member
      end)

    if member?, do: :ok, else: {:error, :class_placement_requires_member}
  end

  def require_member(_context, _user_id), do: {:error, :organization_context_required}

  defp previous_booking(_context, _user_id, nil), do: {:ok, nil}

  defp previous_booking(context, user_id, booking_id) do
    case Scheduling.get_booking(context, booking_id) do
      %{user_id: ^user_id, status: status} = booking when status in [:pending, :approved] ->
        if Map.get(booking, :kind, "member") == "member",
          do: {:ok, booking},
          else: {:error, :not_found}

      _other ->
        {:error, :not_found}
    end
  end

  # ADR-186: moving a member out of a class is also an action on that class.
  defp authorize_previous(_context, nil), do: :ok

  defp authorize_previous(context, previous),
    do: ClassLocation.authorize_class(context, previous.scheduled_class_id)

  defp value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
