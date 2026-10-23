defmodule Palee.Application.DemoSeeders.Schedule do
  @moduledoc """
  ADR-184: a week of classes for the schedule screen: two demo class types,
  two classes a day for the next five days, each with a few approved
  bookings of the mock members. Bookings are written as approved rows
  (`Scheduling.submit_auto_approved_booking/3`), never through
  `SubmitBooking`, so nobody is notified and no entitlement is touched.
  Every class carries one of the demo workouts as its WOD, since a class
  without one is a draft nobody can book (ADR-176).
  """

  @behaviour Palee.Application.DemoSeeder

  alias Palee.Scheduling

  @class_types [{"WOD", "wod"}, {"Strength", "strength"}]
  @days 1..5
  @hours [{7, 0}, {18, 30}]

  @impl true
  def section, do: "schedule"

  @impl true
  def requires, do: ["members", "workouts"]

  @impl true
  def sources, do: ["class_types", "scheduled_classes", "bookings"]

  @impl true
  def seed(context, seeded, now) do
    people = people(seeded)
    workouts = workouts(seeded)

    with {:ok, types, type_rows} <- class_types(context),
         {:ok, class_rows, booking_rows} <- classes(context, types, {people, workouts}, now) do
      {:ok, type_rows ++ class_rows ++ booking_rows}
    end
  end

  defp class_types(context) do
    suffix = :crypto.strong_rand_bytes(2) |> Base.encode16(case: :lower)

    @class_types
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], []}, fn {{name, slug}, index}, {:ok, types, rows} ->
      case Scheduling.create_class_type(context, %{
             name: name,
             slug: "demo-#{slug}-#{suffix}",
             sort_order: 900 + index
           }) do
        {:ok, type} -> {:cont, {:ok, types ++ [type], rows ++ [{"class_types", type.id}]}}
        error -> {:halt, error}
      end
    end)
  end

  defp classes(context, types, {people, workouts}, now) do
    today = DateTime.to_date(now)

    slots =
      for day <- @days, {{hour, minute}, index} <- Enum.with_index(@hours) do
        type = Enum.at(types, rem(day + index, length(types)))
        workout = Enum.at(workouts, rem(day + index, max(length(workouts), 1)))
        {:ok, at} = DateTime.new(Date.add(today, day), Time.new!(hour, minute, 0), "Etc/UTC")
        {type, workout, at}
      end

    Enum.reduce_while(slots, {:ok, [], []}, fn {type, workout, at},
                                               {:ok, class_rows, booking_rows} ->
      with {:ok, slot} <-
             Scheduling.create_slot(context, %{
               class_type_id: type.id,
               master_workout_id: workout,
               name: type.name,
               scheduled_at: at,
               duration_minutes: 60,
               capacity: 12,
               auto_approve: true,
               booking_timeout_minutes: 60
             }),
           {:ok, bookings} <- book(context, slot, people) do
        {:cont, {:ok, class_rows ++ [{"scheduled_classes", slot.id}], booking_rows ++ bookings}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp book(context, slot, people) do
    people
    |> Enum.take_random(min(length(people), Enum.random(3..6)))
    |> Enum.reduce_while({:ok, []}, fn user_id, {:ok, rows} ->
      case Scheduling.submit_auto_approved_booking(context, user_id, slot.id) do
        {:ok, booking} -> {:cont, {:ok, rows ++ [{"bookings", booking.id}]}}
        error -> {:halt, error}
      end
    end)
  end

  defp people(seeded),
    do: for({"users", id} <- Map.get(seeded, "members", []), do: id)

  defp workouts(seeded),
    do: for({"master_workouts", id} <- Map.get(seeded, "workouts", []), do: id)
end
