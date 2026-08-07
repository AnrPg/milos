defmodule MilosTraining.Application.GetCalendarFeed do
  alias MilosTraining.Application.CalendarFeedToken
  alias MilosTraining.{Organizations, Scheduling}
  alias MilosTraining.Workouts.WorkoutStore
  alias MilosTraining.Localization

  @past_days 30
  @future_days 365

  def call(token) do
    with {:ok, user} <- CalendarFeedToken.verify(token) do
      {:ok, build_feed(user)}
    end
  end

  defp build_feed(user) do
    locale = user.preferred_locale || "en"
    now = DateTime.utc_now()
    start_date = Date.utc_today() |> Date.add(-@past_days)
    end_date = Date.utc_today() |> Date.add(@future_days)
    start_at = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_at = DateTime.new!(Date.add(end_date, 1), ~T[00:00:00], "Etc/UTC")

    # A personal calendar spans the gyms its owner attends (F-28), but each
    # gym's data must still be read under that gym's tenant context. Previously
    # this called the un-scoped arities, which resolve to the legacy
    # organization - so every user's feed carried the legacy gym's classes, and
    # a global admin's carried every athlete's assignments (F-18/F-29).
    events =
      user
      |> active_tenant_contexts()
      |> Enum.flat_map(fn context ->
        class_events(context, user, start_at, end_at, locale) ++
          assignment_events(context, user, start_date, end_date, locale)
      end)

    render_ics(events, now)
  end

  defp active_tenant_contexts(user) do
    user.id
    |> Organizations.list_memberships()
    |> Enum.filter(&(&1.membership.status == :active))
    |> Enum.flat_map(fn %{organization: organization} ->
      case Organizations.resolve_tenant_context(user, organization.slug) do
        {:ok, context} -> [context]
        _unavailable -> []
      end
    end)
  end

  # Role comes from the membership in this organization, never the account.
  defp organization_admin?(context), do: context.role in [:owner, :admin, :coach]

  defp class_events(context, user, start_at, end_at, locale) do
    if context.role == :athlete do
      []
    else
      do_class_events(context, user, start_at, end_at, locale)
    end
  end

  defp do_class_events(context, user, start_at, end_at, locale) do
    slots =
      Scheduling.get_calendar_week(context, %{start_at: start_at, end_at: end_at})
      |> Enum.filter(&include_slot?(&1, user, organization_admin?(context)))

    if organization_admin?(context) do
      recurring_events =
        slots
        |> Enum.filter(& &1.class_series_id)
        |> Enum.group_by(& &1.class_series_id)
        |> Enum.map(fn {_series_id, [slot | _]} ->
          recurring_class_event(slot, user, locale, true)
        end)

      one_off_events =
        slots
        |> Enum.reject(& &1.class_series_id)
        |> Enum.map(&class_event(&1, user, locale, true))

      recurring_events ++ one_off_events
    else
      Enum.map(slots, &class_event(&1, user, locale, false))
    end
  end

  defp class_event(slot, user, locale, admin?) do
    %{
      uid: "class-#{slot.id}@trainingjournal",
      title: translate(locale, "Class: %{name}", %{name: class_name(slot)}),
      starts_at: slot.scheduled_at,
      ends_at: DateTime.add(slot.scheduled_at, slot.duration_minutes * 60, :second),
      description: class_description(slot, user, locale, admin?)
    }
  end

  defp recurring_class_event(slot, user, locale, admin?) do
    series = slot.class_series

    %{
      uid: "class-series-#{series.id}@trainingjournal",
      title: translate(locale, "Class: %{name}", %{name: series.name}),
      recurrence: series,
      starts_at: slot.scheduled_at,
      duration_minutes: series.duration_minutes,
      description: class_description(slot, user, locale, admin?)
    }
  end

  defp assignment_events(context, user, start_date, end_date, locale) do
    cond do
      context.role == :member ->
        []

      organization_admin?(context) ->
        WorkoutStore.list_assigned_workouts_for_admin(context, start_date, end_date)
        |> Enum.map(&assignment_event(&1, locale))

      true ->
        WorkoutStore.list_assigned_workouts_for_athlete(context, user.id, start_date, end_date)
        |> Enum.map(&assignment_event(&1, locale))
    end
  end

  defp assignment_event(assignment, locale) do
    scheduled_for = date_value(assignment.scheduled_for)

    title =
      assignment
      |> get_in([:workout, :title])
      |> case do
        nil -> translate(locale, "Assigned workout")
        "" -> translate(locale, "Assigned workout")
        value -> translate(locale, "Workout: %{title}", %{title: value})
      end

    %{
      uid: "assigned-workout-#{assignment.id}@trainingjournal",
      title: title,
      starts_on: scheduled_for,
      ends_on: Date.add(scheduled_for, 1),
      description: translate(locale, "Assigned workout in TrainingJournal.")
    }
  end

  defp date_value(%Date{} = date), do: date
  defp date_value(value) when is_binary(value), do: Date.from_iso8601!(value)

  defp include_slot?(_slot, _user, true = _admin?), do: true

  defp include_slot?(slot, user, _admin?) do
    Enum.any?(slot.bookings || [], fn booking ->
      booking.user_id == user.id and booking.status in [:pending, :approved]
    end)
  end

  defp class_description(slot, _user, locale, true = _admin?) do
    translate(locale, "Scheduled %{name} class in TrainingJournal.", %{name: class_name(slot)})
  end

  defp class_description(slot, user, locale, _admin?) do
    booking =
      Enum.find(slot.bookings || [], fn booking ->
        booking.user_id == user.id and booking.status in [:pending, :approved]
      end)

    status = if booking, do: booking.status, else: "scheduled"
    localized_status = translate(locale, status_message(status))

    translate(locale, "TrainingJournal class booking status: %{status}.", %{
      status: localized_status
    })
  end

  defp render_ics(events, now) do
    lines =
      [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//TrainingJournal//Calendar Feed//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "X-WR-CALNAME:TrainingJournal",
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

  defp event_lines(%{recurrence: series, starts_at: starts_at} = event, now) do
    [
      "BEGIN:VEVENT",
      "UID:#{escape(event.uid)}",
      "DTSTAMP:#{format_datetime(now)}",
      "DTSTART;TZID=#{escape(series.timezone)}:#{format_zoned_datetime(starts_at, series.timezone)}",
      "DURATION:PT#{event.duration_minutes}M",
      recurrence_rule(series),
      excluded_dates(series),
      "SUMMARY:#{escape(event.title)}",
      "DESCRIPTION:#{escape(event.description)}",
      "END:VEVENT"
    ]
    |> Enum.reject(&is_nil/1)
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

  defp class_type_name(%{class_type: %{name: name}}) when is_binary(name), do: name
  defp class_type_name(_slot), do: "—"

  defp class_name(%{name: name}) when is_binary(name) and name != "Class", do: name
  defp class_name(slot), do: class_type_name(slot)

  defp recurrence_rule(series) do
    byday = series.weekdays |> Enum.map(&weekday_code/1) |> Enum.join(",")
    until_part = if series.ends_on, do: ";UNTIL=#{format_date(series.ends_on)}T235959Z", else: ""
    "RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=#{byday}#{until_part}"
  end

  defp excluded_dates(%{excluded_dates: []}), do: nil
  defp excluded_dates(%{excluded_dates: nil}), do: nil

  defp excluded_dates(series) do
    dates =
      series.excluded_dates
      |> Enum.map(&format_local_datetime(&1, series.local_start_time))
      |> Enum.join(",")

    "EXDATE;TZID=#{escape(series.timezone)}:#{dates}"
  end

  defp weekday_code(1), do: "MO"
  defp weekday_code(2), do: "TU"
  defp weekday_code(3), do: "WE"
  defp weekday_code(4), do: "TH"
  defp weekday_code(5), do: "FR"
  defp weekday_code(6), do: "SA"
  defp weekday_code(7), do: "SU"

  defp status_message(:pending), do: "Pending"
  defp status_message(:approved), do: "Approved"
  defp status_message("scheduled"), do: "Scheduled"
  defp status_message(status), do: to_string(status)

  defp translate(locale, message, bindings \\ %{}),
    do: Localization.translate(locale, message, bindings, "calendar")

  defp format_datetime(datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  defp format_date(date), do: Calendar.strftime(date, "%Y%m%d")

  defp format_local_datetime(date, time) do
    Calendar.strftime(date, "%Y%m%d") <> "T" <> Calendar.strftime(time, "%H%M%S")
  end

  defp format_zoned_datetime(datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%Y%m%dT%H%M%S")
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\n", "\\n")
  end
end
