defmodule Palee.Application.BoxScreens.BoxScreenToday do
  @moduledoc """
  What a box screen shows today (ADR-253), read in the box's scope:

    * the day on the box's own clock (its time zone, never UTC or a fixed
      zone): the classes of the screen's branch and the whole-box classes
      (every class for a whole-box screen), drafts left out;
    * each class's WOD with its `body` (ADR-224), once per WOD;
    * a leaderboard per WOD (`WorkoutDayLeaderboard`, as the `#wod-σήμερα`
      card), only people who opted in, never journal-private results;
    * bookings per class: first names only, hidden people and guest or trial
      seats only counted (`ScreenPrivacy`);
    * the `focus`: automatic (preview, timer, results, idle) or the staff
      override, with `source: auto | staff`.
  """

  alias Palee.{BoxScreens, Community, Facility, Identity, Organizations, Scheduling, Workouts}
  alias Palee.Application.WorkoutDayLeaderboard
  alias Palee.BoxScreens.Domain.ScreenPrivacy
  alias Palee.TimeZones.ZonedTime

  @leaderboard_size 10

  @doc "The whole day for `screen` at `now`."
  def build(context, screen, %DateTime{} = now) do
    day = day(context, now)
    classes = classes(context, screen, day)
    workouts = workouts(context, classes)
    results = Map.new(workouts, &{&1.id, WorkoutDayLeaderboard.results(context, &1.id, day.from, day.to)})

    people_ids =
      Enum.flat_map(classes, &[&1.coach_user_id | ScreenPrivacy.nameable_user_ids(&1.bookings)]) ++
        Enum.flat_map(Map.values(results), fn rows -> Enum.map(rows, & &1.user_id) end)

    {hidden, names} = people(people_ids)

    %{
      box: %{name: box_name(context)},
      screen: %{id: screen.id, name: screen.name, branch: branch(context, screen.location_id)},
      date: day.date,
      time_zone: day.zone,
      server_now: now,
      classes: Enum.map(classes, &class_view(&1, hidden, names)),
      workouts: Enum.map(workouts, &workout_view/1),
      leaderboards:
        Enum.map(workouts, &leaderboard(context, &1, day, Map.fetch!(results, &1.id), hidden, names)),
      focus:
        BoxScreens.focus(
          Enum.map(classes, &focus_class/1),
          BoxScreens.active_override(screen, now),
          now
        )
    }
  end

  @doc "The ids of today's classes the screen shows (an override may name one)."
  def slot_ids(context, screen, %DateTime{} = now) do
    day = day(context, now)
    context |> classes(screen, day) |> Enum.map(& &1.id)
  end

  @doc "Whether the screen shows `slot` (its branch or the whole box)."
  def shows?(%{location_id: nil}, _slot), do: true
  def shows?(%{location_id: location_id}, %{location_id: slot_location}),
    do: slot_location in [nil, location_id]

  defp day(context, now) do
    zone = Organizations.organization_timezone(context.organization_id)
    date = ZonedTime.local_date(now, zone)

    %{
      zone: zone,
      date: date,
      from: ZonedTime.start_of_day(date, zone),
      to: ZonedTime.start_of_day(Date.add(date, 1), zone)
    }
  end

  defp classes(context, screen, day) do
    case Scheduling.get_calendar_week(context, %{start_at: day.from, end_at: day.to}) do
      slots when is_list(slots) ->
        slots
        |> Enum.filter(&shows?(screen, &1))
        |> Enum.sort_by(& &1.scheduled_at, DateTime)

      _error ->
        []
    end
  end

  defp workouts(context, classes) do
    classes
    |> Enum.map(& &1.master_workout_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(&Workouts.get_workout(context, &1))
    |> Enum.filter(&is_map/1)
  end

  defp people(ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    case ids do
      [] ->
        {MapSet.new(), %{}}

      ids ->
        hidden = ids |> Community.hidden_member_ids() |> MapSet.new()

        names =
          ids
          |> Enum.reject(&MapSet.member?(hidden, &1))
          |> Identity.list_by_ids()
          |> Map.new(&{&1.id, &1.nickname})

        {hidden, names}
    end
  end

  defp class_view(slot, hidden, names) do
    %{
      id: slot.id,
      name: slot.name,
      class_type: slot.class_type && slot.class_type.name,
      scheduled_at: slot.scheduled_at,
      ends_at: BoxScreens.ends_at(slot),
      duration_minutes: slot.duration_minutes,
      location_id: slot.location_id,
      cancelled: not is_nil(slot.cancelled_at),
      coach_name: coach_name(slot.coach_user_id, hidden, names),
      workout_id: slot.master_workout_id,
      bookings: ScreenPrivacy.bookings(slot.bookings, slot.capacity, hidden, names)
    }
  end

  defp coach_name(nil, _hidden, _names), do: nil

  defp coach_name(id, hidden, names) do
    if MapSet.member?(hidden, id), do: nil, else: ScreenPrivacy.first_name(Map.get(names, id))
  end

  defp workout_view(workout) do
    %{
      id: workout.id,
      title: workout.title,
      type: workout |> Map.get(:type) |> then(&(&1 && to_string(&1))),
      body: Map.get(workout, :body)
    }
  end

  defp leaderboard(context, workout, day, results, hidden, names) do
    %{section: section, rows: rows} =
      WorkoutDayLeaderboard.rank(context, workout, day.from, day.to,
        results: results,
        exclude_user_ids: MapSet.to_list(hidden),
        limit: @leaderboard_size
      )

    %{
      workout_id: workout.id,
      score: section && Map.take(section, [:name, :score_type, :unit]),
      entries:
        rows
        |> Enum.map(fn row ->
          %{
            rank: row.rank,
            name: ScreenPrivacy.first_name(Map.get(names, row.user_id)),
            value: row.value,
            unit: row.unit,
            scale_level_slug: row.scale_level_slug
          }
        end)
        |> Enum.reject(&is_nil(&1.name))
    }
  end

  defp focus_class(slot) do
    %{
      id: slot.id,
      scheduled_at: slot.scheduled_at,
      duration_minutes: slot.duration_minutes,
      cancelled: not is_nil(slot.cancelled_at)
    }
  end

  defp box_name(%{organization: %{name: name}}), do: name
  defp box_name(_context), do: nil

  defp branch(_context, nil), do: nil

  defp branch(context, location_id) do
    case Facility.get_location(context, location_id) do
      %{id: id, name: name} -> %{id: id, name: name}
      _missing -> nil
    end
  end
end
