defmodule MilosTraining.Application.GetCalendarFeed do
  alias MilosTraining.Application.CalendarFeedToken
  alias MilosTraining.{Scheduling, Workouts}

  @past_days 30
  @future_days 365

  def call(token) do
    with {:ok, user} <- CalendarFeedToken.verify(token) do
      {:ok, build_feed(user)}
    end
  end

  defp build_feed(user) do
    now = DateTime.utc_now()
    start_date = Date.utc_today() |> Date.add(-@past_days)
    end_date = Date.utc_today() |> Date.add(@future_days)
    start_at = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_at = DateTime.new!(Date.add(end_date, 1), ~T[00:00:00], "Etc/UTC")

    events =
      class_events(user, start_at, end_at) ++
        assignment_events(user, start_date, end_date)

    render_ics(events, now)
  end

  defp class_events(%{role: :athlete}, _start_at, _end_at), do: []

  defp class_events(user, start_at, end_at) do
    %{start_at: start_at, end_at: end_at}
    |> Scheduling.get_calendar_week()
    |> Enum.filter(&include_slot?(&1, user))
    |> Enum.map(fn slot ->
      %{
        uid: "class-#{slot.id}@milos-training",
        title: "Class: #{format_training_type(slot.training_type)}",
        starts_at: slot.scheduled_at,
        ends_at: DateTime.add(slot.scheduled_at, 60 * 60, :second),
        description: class_description(slot, user)
      }
    end)
  end

  defp assignment_events(%{role: :member}, _start_date, _end_date), do: []

  defp assignment_events(%{role: :admin}, start_date, end_date) do
    Workouts.list_assigned_workouts_for_admin(start_date, end_date)
    |> Enum.map(&assignment_event/1)
  end

  defp assignment_events(user, start_date, end_date) do
    Workouts.list_assigned_workouts_for_athlete(user.id, start_date, end_date)
    |> Enum.map(&assignment_event/1)
  end

  defp assignment_event(assignment) do
    title =
      assignment
      |> get_in([:workout, :title])
      |> case do
        nil -> "Assigned workout"
        "" -> "Assigned workout"
        value -> "Workout: #{value}"
      end

    %{
      uid: "assigned-workout-#{assignment.id}@milos-training",
      title: title,
      starts_on: assignment.scheduled_for,
      ends_on: Date.add(assignment.scheduled_for, 1),
      description: "Assigned workout in Milos Training."
    }
  end

  defp include_slot?(_slot, %{role: :admin}), do: true

  defp include_slot?(slot, user) do
    Enum.any?(slot.bookings || [], fn booking ->
      booking.user_id == user.id and booking.status in [:pending, :approved]
    end)
  end

  defp class_description(slot, %{role: :admin}) do
    "Scheduled #{format_training_type(slot.training_type)} class in Milos Training."
  end

  defp class_description(slot, user) do
    booking =
      Enum.find(slot.bookings || [], fn booking ->
        booking.user_id == user.id and booking.status in [:pending, :approved]
      end)

    status = if booking, do: booking.status, else: "scheduled"
    "Milos Training class booking status: #{status}."
  end

  defp render_ics(events, now) do
    lines =
      [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Milos Training//Calendar Feed//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "X-WR-CALNAME:Milos Training",
        Enum.map(events, &event_lines(&1, now)),
        "END:VCALENDAR"
      ]
      |> List.flatten()

    Enum.join(lines, "\r\n") <> "\r\n"
  end

  defp event_lines(%{starts_at: starts_at, ends_at: ends_at} = event, now) do
    [
      "BEGIN:VEVENT",
      "UID:#{escape(event.uid)}",
      "DTSTAMP:#{format_datetime(now)}",
      "DTSTART:#{format_datetime(starts_at)}",
      "DTEND:#{format_datetime(ends_at)}",
      "SUMMARY:#{escape(event.title)}",
      "DESCRIPTION:#{escape(event.description)}",
      "END:VEVENT"
    ]
  end

  defp event_lines(%{starts_on: starts_on, ends_on: ends_on} = event, now) do
    [
      "BEGIN:VEVENT",
      "UID:#{escape(event.uid)}",
      "DTSTAMP:#{format_datetime(now)}",
      "DTSTART;VALUE=DATE:#{format_date(starts_on)}",
      "DTEND;VALUE=DATE:#{format_date(ends_on)}",
      "SUMMARY:#{escape(event.title)}",
      "DESCRIPTION:#{escape(event.description)}",
      "END:VEVENT"
    ]
  end

  defp format_training_type(type) do
    type
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_datetime(datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  defp format_date(date), do: Calendar.strftime(date, "%Y%m%d")

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\n", "\\n")
  end
end
