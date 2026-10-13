defmodule MilosTraining.Application.PlaceMemberInClass do
  @moduledoc """
  Lets an admin book a member into a scheduled class from the member's profile,
  optionally moving them out of one of their existing bookings.

  The new booking goes through the regular member booking flow (capacity,
  timing and entitlement checks) and is approved immediately, since the admin
  is the one placing the member. The previous booking is withdrawn only after
  the new one succeeds, so a failed move never leaves the member without a
  class.
  """

  alias MilosTraining.Application.{ResolveBooking, SubmitBooking, WithdrawBooking}
  alias MilosTraining.{Identity, Organizations, Scheduling}

  def call(context, user_id, params) do
    slot_id = value(params, :slot_id)
    from_booking_id = value(params, :from_booking_id)

    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found},
         :ok <- require_member(context, user.id),
         {:ok, previous} <- previous_booking(context, user.id, from_booking_id),
         {:ok, booking} <- SubmitBooking.call(context, user, slot_id),
         {:ok, booking} <- approve(context, booking),
         {:ok, _withdrawn} <- withdraw_previous(context, user.id, previous) do
      {:ok, %{booking: booking, previous_booking_id: previous && previous.id}}
    end
  end

  defp require_member(%{organization_id: organization_id}, user_id) do
    member? =
      user_id
      |> Organizations.list_memberships()
      |> Enum.any?(fn %{membership: membership, organization: organization} ->
        organization.id == organization_id and membership.status == :active and
          membership.role == :member
      end)

    if member?, do: :ok, else: {:error, :class_placement_requires_member}
  end

  defp require_member(_context, _user_id), do: {:error, :organization_context_required}

  defp previous_booking(_context, _user_id, nil), do: {:ok, nil}

  defp previous_booking(context, user_id, booking_id) do
    case Scheduling.get_booking(context, booking_id) do
      %{user_id: ^user_id, status: status} = booking when status in [:pending, :approved] ->
        {:ok, booking}

      _other ->
        {:error, :not_found}
    end
  end

  defp approve(context, %{status: :pending, id: booking_id}) do
    with {:ok, booking, _outcome} <-
           ResolveBooking.call(context, booking_id, %{action: :approve}),
         do: {:ok, booking}
  end

  defp approve(_context, booking), do: {:ok, booking}

  defp withdraw_previous(_context, _user_id, nil), do: {:ok, nil}

  defp withdraw_previous(context, user_id, previous),
    do: WithdrawBooking.call(context, user_id, previous.id)

  defp value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
