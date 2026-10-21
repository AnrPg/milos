defmodule MilosTraining.Application.ProviderTodayItems do
  @moduledoc """
  The default `Ports.ProviderToday` (ADR-162): in one provider's tenant
  context, as the member, the day's booked classes, appointments, the
  coach's programme for the day and the box's WOD.
  """

  @behaviour MilosTraining.Application.Ports.ProviderToday

  alias MilosTraining.Application.{GetWodTodayCard, MyProviders}
  alias MilosTraining.{Appointments, Scheduling, Workouts}

  @impl true
  def items(tenant, user_id, %Date{} = date, timezone) do
    {from, to} = window(date, timezone)

    classes =
      tenant
      |> Scheduling.list_member_slots(user_id, from, to)
      |> Enum.map(fn slot ->
        %{
          kind: "class",
          id: slot.id,
          at: slot.scheduled_at,
          title: MyProviders.slot_title(slot),
          status: slot.user_booking && to_string(slot.user_booking.status)
        }
      end)

    appointments =
      tenant
      |> Appointments.list_bookings(%{user_id: user_id})
      |> Enum.filter(&(&1.status == "booked" and is_nil(&1.slot.cancelled_at)))
      |> Enum.filter(&within?(&1.slot.starts_at, from, to))
      |> Enum.map(fn booking ->
        %{
          kind: "appointment",
          id: booking.id,
          at: booking.slot.starts_at,
          title: booking.slot.kind && to_string(booking.slot.kind),
          status: booking.status
        }
      end)

    programme =
      tenant
      |> Workouts.list_assigned_workouts_for_athlete(user_id, date, date)
      |> Enum.reject(&(&1[:my_athlete_status] in ["rejected", "archived"]))
      |> Enum.map(fn assignment ->
        %{
          kind: "program",
          id: assignment.id,
          at: nil,
          title: assignment.workout && assignment.workout.title,
          status: assignment[:execution_status] || assignment[:my_athlete_status]
        }
      end)

    {:ok, classes ++ appointments ++ programme ++ wod(tenant, date, timezone, classes)}
  end

  # The box's WOD, unless a booked class already shows it.
  defp wod(tenant, date, timezone, classes) do
    case GetWodTodayCard.call(tenant, %{"date" => Date.to_iso8601(date), "timezone" => timezone}) do
      {:ok, %{workout: %{id: id, title: title}, classes: wod_classes, logged_by_me: logged?}} ->
        booked = MapSet.new(classes, & &1.id)

        if Enum.any?(wod_classes, &MapSet.member?(booked, &1.id)),
          do: [],
          else: [%{kind: "wod", id: id, at: nil, title: title, status: if(logged?, do: "logged")}]

      _none ->
        []
    end
  end

  defp window(date, timezone) do
    from = date |> DateTime.new!(~T[00:00:00], timezone) |> DateTime.shift_zone!("Etc/UTC")

    to =
      date
      |> Date.add(1)
      |> DateTime.new!(~T[00:00:00], timezone)
      |> DateTime.shift_zone!("Etc/UTC")

    {from, to}
  end

  defp within?(%DateTime{} = at, from, to),
    do: DateTime.compare(at, from) != :lt and DateTime.compare(at, to) == :lt

  defp within?(_at, _from, _to), do: false
end
