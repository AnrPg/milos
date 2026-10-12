defmodule MilosTraining.Application.ListOfferedAppointmentSlots do
  @moduledoc """
  Upcoming slots a client can book (ADR-098): open, with room, and matching
  the format, coach and session length of a package they hold for that kind.
  """

  alias MilosTraining.{Appointments, Finance}
  alias MilosTraining.Appointments.Domain.AppointmentPolicy

  @horizon_days 60

  def call(context, %{id: user_id}, now \\ DateTime.utc_now()) do
    context
    |> Appointments.list_slots(%{
      from: now,
      to: DateTime.add(now, @horizon_days * 86_400),
      open: true
    })
    |> Enum.filter(fn slot ->
      terms =
        Finance.allowance_terms(
          context,
          user_id,
          AppointmentPolicy.allowance(slot),
          DateTime.to_date(slot.starts_at)
        )

      booked? = Enum.any?(slot.bookings, &(&1.user_id == user_id))

      terms != nil and
        (booked? or (slot.spots_remaining > 0 and AppointmentPolicy.offered?(slot, terms)))
    end)
    |> Enum.map(fn slot ->
      slot
      |> Map.put(:booked_by_me, Enum.any?(slot.bookings, &(&1.user_id == user_id)))
      |> Map.put(:bookings, [])
    end)
  end
end
