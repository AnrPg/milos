defmodule MilosTraining.Application.ListOfferedAppointmentSlots do
  @moduledoc """
  Upcoming slots a client can book (ADR-098): open, with room, and matching
  the format, coach and session length of a package they hold for that kind.
  """

  alias MilosTraining.{Appointments, Finance, Identity}
  alias MilosTraining.Appointments.Domain.AppointmentPolicy

  @horizon_days 60

  def call(context, %{id: user_id}, now \\ DateTime.utc_now()) do
    slots = offered(context, user_id, now)

    coaches =
      slots
      |> Enum.map(& &1.coach_id)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    Enum.map(slots, &Map.put(&1, :coach_nickname, Map.get(coaches, &1.coach_id)))
  end

  defp offered(context, user_id, now) do
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
      booked? = Enum.any?(slot.bookings, &(&1.user_id == user_id))

      slot
      |> Map.put(:booked_by_me, booked?)
      # ADR-170: the call link is for the people in the session only.
      |> Map.put(:meeting_url, if(booked?, do: slot[:meeting_url]))
      |> Map.put(:bookings, [])
    end)
  end
end
