defmodule MilosTraining.Infrastructure.Appointments.EctoAppointmentStore do
  @moduledoc "Ecto adapter of the Appointments store (ADR-098)."

  @behaviour MilosTraining.Appointments.Ports.AppointmentStore

  import Ecto.Query

  alias MilosTraining.Appointments.{Booking, Slot}
  alias MilosTraining.Repo

  @active "booked"

  @impl true
  def create_slot(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.put("organization_id", organization_id)
    |> Slot.create_changeset()
    |> Repo.insert()
    |> case do
      {:ok, slot} -> {:ok, normalize_slot(slot, [])}
      error -> error
    end
  end

  @impl true
  def get_slot(%{organization_id: organization_id}, id) do
    case fetch(Slot, organization_id, id) do
      nil -> nil
      slot -> normalize_slot(slot, active_bookings(slot.id))
    end
  end

  @impl true
  def list_slots(%{organization_id: organization_id}, filters) do
    slots =
      Slot
      |> where([slot], slot.organization_id == ^organization_id)
      |> maybe_where(:from, filters[:from])
      |> maybe_where(:to, filters[:to])
      |> maybe_where(:coach_id, filters[:coach_id])
      |> maybe_where(:open, filters[:open])
      |> order_by([slot], asc: slot.starts_at)
      |> limit(500)
      |> Repo.all()

    bookings = slots |> Enum.map(& &1.id) |> active_bookings_by_slot()
    Enum.map(slots, &normalize_slot(&1, Map.get(bookings, &1.id, [])))
  end

  @impl true
  def cancel_slot(%{organization_id: organization_id}, id) do
    case fetch(Slot, organization_id, id) do
      nil ->
        {:error, :not_found}

      slot ->
        slot
        |> Slot.cancel_changeset(slot.cancelled_at || DateTime.utc_now())
        |> Repo.update()
        |> case do
          {:ok, slot} -> {:ok, normalize_slot(slot, active_bookings(slot.id))}
          error -> error
        end
    end
  end

  # The slot row is locked while capacity is checked, so concurrent bookings
  # cannot overfill it.
  @impl true
  def create_booking(%{organization_id: organization_id}, attrs, check) do
    Repo.transaction(fn ->
      slot =
        Slot
        |> where([slot], slot.id == ^attrs.slot_id and slot.organization_id == ^organization_id)
        |> lock("FOR UPDATE")
        |> Repo.one() || Repo.rollback(:not_found)

      bookings = active_bookings(slot.id)

      with :ok <- check.(normalize_slot(slot, bookings), bookings),
           {:ok, booking} <-
             attrs
             |> Map.put(:organization_id, organization_id)
             |> Booking.create_changeset()
             |> Repo.insert() do
        normalize_booking(booking)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def get_booking(%{organization_id: organization_id}, id) do
    case fetch(Booking, organization_id, id) do
      nil ->
        nil

      booking ->
        booking
        |> normalize_booking()
        |> Map.put(:slot, get_slot(%{organization_id: organization_id}, booking.slot_id))
    end
  end

  @impl true
  def list_bookings(%{organization_id: organization_id}, filters) do
    Booking
    |> where([booking], booking.organization_id == ^organization_id)
    |> maybe_where(:user_id, filters[:user_id])
    |> maybe_where(:slot_id, filters[:slot_id])
    |> join(:inner, [booking], slot in Slot, on: slot.id == booking.slot_id)
    |> order_by([_booking, slot], desc: slot.starts_at)
    |> limit(200)
    |> select([booking, slot], {booking, slot})
    |> Repo.all()
    |> Enum.map(fn {booking, slot} ->
      booking |> normalize_booking() |> Map.put(:slot, normalize_slot(slot, nil))
    end)
  end

  @impl true
  def cancel_booking(%{organization_id: organization_id}, id, late?) do
    update_booking(organization_id, id, &Booking.cancel_changeset(&1, late?, DateTime.utc_now()))
  end

  @impl true
  def record_attendance(%{organization_id: organization_id}, id, status) do
    update_booking(organization_id, id, &Booking.attendance_changeset(&1, status))
  end

  defp update_booking(organization_id, id, changeset) do
    case fetch(Booking, organization_id, id) do
      nil ->
        {:error, :not_found}

      booking ->
        booking
        |> changeset.()
        |> Repo.update()
        |> case do
          {:ok, booking} -> {:ok, normalize_booking(booking)}
          error -> error
        end
    end
  end

  defp maybe_where(query, _key, nil), do: query
  defp maybe_where(query, :from, from), do: where(query, [slot], slot.starts_at >= ^from)
  defp maybe_where(query, :to, to), do: where(query, [slot], slot.starts_at < ^to)
  defp maybe_where(query, :coach_id, id), do: where(query, [slot], slot.coach_id == ^id)
  defp maybe_where(query, :open, true), do: where(query, [slot], is_nil(slot.cancelled_at))
  defp maybe_where(query, :open, _all), do: query
  defp maybe_where(query, :user_id, id), do: where(query, [booking], booking.user_id == ^id)
  defp maybe_where(query, :slot_id, id), do: where(query, [booking], booking.slot_id == ^id)

  defp active_bookings(slot_id),
    do: [slot_id] |> active_bookings_by_slot() |> Map.get(slot_id, [])

  defp active_bookings_by_slot([]), do: %{}

  defp active_bookings_by_slot(slot_ids) do
    Booking
    |> where([booking], booking.slot_id in ^slot_ids and booking.status == @active)
    |> join(:left, [booking], user in "users", on: user.id == booking.user_id)
    |> select([booking, user], {booking, user.nickname})
    |> Repo.all()
    |> Enum.map(fn {booking, nickname} ->
      booking |> normalize_booking() |> Map.put(:nickname, nickname)
    end)
    |> Enum.group_by(& &1.slot_id)
  end

  defp fetch(schema, organization_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(schema, id: id, organization_id: organization_id)
      :error -> nil
    end
  end

  defp normalize_slot(%Slot{} = slot, bookings) do
    slot
    |> Map.take([
      :id,
      :coach_id,
      :kind,
      :format,
      :starts_at,
      :duration_minutes,
      :capacity,
      :location_id,
      :notes,
      :mode,
      :meeting_url,
      :cancelled_at
    ])
    |> Map.merge(%{
      bookings: bookings || [],
      spots_remaining: if(bookings, do: max(slot.capacity - length(bookings), 0))
    })
  end

  defp normalize_booking(%Booking{} = booking) do
    Map.take(booking, [
      :id,
      :slot_id,
      :user_id,
      :status,
      :allowance,
      :reservation_id,
      :booked_by_id,
      :late_cancellation,
      :cancelled_at,
      :inserted_at
    ])
  end
end
