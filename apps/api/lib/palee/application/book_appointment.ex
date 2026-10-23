defmodule Palee.Application.BookAppointment do
  @moduledoc """
  Books a client into an appointment slot (ADR-098). Clients book themselves;
  staff may book on a client's behalf. One unit of the slot's allowance is
  reserved through the ledger and kept until the session is used or cancelled.
  """

  alias Palee.Application.{AppointmentLedger, GoLive, NotifyAppointment}
  alias Palee.{Appointments, Finance, Identity, Organizations}
  alias Palee.Appointments.Domain.AppointmentPolicy

  def call(context, actor, slot_id, for_user_id \\ nil) do
    now = DateTime.utc_now()

    with {:ok, client} <- client(context, actor, for_user_id),
         # ADR-184: a business in demo mode takes no bookings from real people.
         :ok <- GoLive.check_booking(context, client.id),
         %{} = slot <- Appointments.get_slot(context, slot_id) || {:error, :not_found},
         :ok <- AppointmentPolicy.can_book?(slot, slot.bookings, client.id, now),
         :ok <- terms_allow(context, client, slot),
         id = Ecto.UUID.generate(),
         {:ok, reservation} <- reserve(context, client, slot, id) do
      attrs = %{
        id: id,
        slot_id: slot.id,
        user_id: client.id,
        allowance: Atom.to_string(AppointmentPolicy.allowance(slot)),
        reservation_id: Map.get(reservation, :id),
        booked_by_id: actor.id
      }

      check = fn locked_slot, bookings ->
        AppointmentPolicy.can_book?(locked_slot, bookings, client.id, now)
      end

      case Appointments.create_booking(context, attrs, check) do
        {:ok, booking} ->
          NotifyAppointment.booked(
            Map.put_new(slot, :organization_id, context.organization_id),
            client
          )

          {:ok, Map.put(booking, :slot, slot)}

        {:error, reason} ->
          AppointmentLedger.release(
            context,
            %{id: id, reservation_id: attrs.reservation_id},
            "Appointment was not booked"
          )

          {:error, reason}
      end
    end
  end

  defp client(_context, actor, nil), do: {:ok, actor}
  defp client(_context, %{id: id} = actor, id), do: {:ok, actor}

  defp client(context, _actor, user_id) do
    cond do
      not (Organizations.can?(context, :book_for_clients) or
               Organizations.can?(context, :manage_appointments)) ->
        {:error, :forbidden}

      user_id not in Organizations.list_active_membership_user_ids(context.organization_id) ->
        {:error, :not_found}

      true ->
        {:ok, Identity.find_by_id(user_id)}
    end
  end

  defp terms_allow(context, client, slot) do
    case Finance.allowance_terms(
           context,
           client.id,
           AppointmentPolicy.allowance(slot),
           Organizations.local_date(context, slot.starts_at)
         ) do
      nil -> :ok
      terms -> AppointmentPolicy.terms_allow?(slot, terms)
    end
  end

  # The client's own role decides enforcement, also when staff book for them.
  defp reserve(context, client, slot, id) do
    request =
      slot
      |> AppointmentPolicy.entitlement_request()
      |> Map.merge(%{
        actor_role: client.role,
        source_context: "appointments",
        source_id: id,
        idempotency_key: "appointment:#{id}"
      })

    Finance.reserve_entitlement(context, client.id, request)
  end
end
