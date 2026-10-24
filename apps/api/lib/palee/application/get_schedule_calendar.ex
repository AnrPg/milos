defmodule Palee.Application.GetScheduleCalendar do
  alias Palee.{Community, Facility, Finance, Identity, Organizations, Scheduling, Workouts}
  alias Palee.Application.BookingTerms
  alias Palee.Scheduling.Domain.BookingPolicy
  alias Palee.TimeZones.ZonedTime

  def call(%{organization_id: organization_id} = context, actor, params)
      when is_binary(organization_id) do
    with {:ok, window, days, class_type_ids} <- normalize_window(params) do
      # ADR-179: a window given as dates covers the gym's own days.
      zone = Organizations.organization_timezone(organization_id)
      {start_at, end_at} = window_bounds(window, days, zone)

      slots =
        get_calendar_week(context, %{
          start_at: start_at,
          end_at: end_at,
          class_type_ids: class_type_ids,
          # ADR-176: only staff see draft classes (no WOD yet).
          include_drafts: admin_role?(context, actor)
        })
        |> scope_located(context, actor)
        |> enrich_slots(context, actor)
        |> put_workout_status(context)
        |> put_package_coverage(context, actor)
        |> put_cancel_free_until(context, actor)
        |> put_friends_going(context, actor)

      class_types = schedule_class_types(context, slots)

      {:ok,
       %{
         start_date: ZonedTime.local_date(start_at, zone),
         end_date: ZonedTime.local_date(DateTime.add(end_at, -1, :second), zone),
         days: days,
         class_types: class_types,
         locations:
           context
           |> Facility.list_locations(include_archived: true)
           |> scope_located(context, actor, & &1.id),
         coaches: schedule_coaches(slots),
         slots: slots
       }}
    end
  end

  def call(_context, _actor, _params), do: {:error, :organization_context_required}

  def call(_actor, _params), do: {:error, :organization_context_required}

  defp get_calendar_week(context, params), do: Scheduling.get_calendar_week(context, params)

  # ADR-186: branch-scoped staff plan and run the classes of their own
  # branches. Someone who also trains keeps the whole schedule in the client
  # view (no rosters), because their package decides where they may book.
  defp scope_located(items, context, actor, location_of \\ &Map.get(&1, :location_id)) do
    if Organizations.location_scope(context) != :all and
         (admin_role?(context, actor) or not trains_here?(context)),
       do: Organizations.filter_by_location_scope(context, items, location_of),
       else: items
  end

  defp trains_here?(context),
    do: Enum.any?(Map.get(context, :roles) || [], &(&1 in [:member, :athlete]))

  # ADR-176: `published` and `workout_status` (linked | awaiting | missing,
  # the incomplete badge), with days read in the gym's time zone.
  defp put_workout_status([], _context), do: []

  defp put_workout_status(slots, context) do
    now = DateTime.utc_now()
    zone = Organizations.organization_timezone(context.organization_id)

    Enum.map(slots, fn slot ->
      Map.merge(slot, %{
        published: Scheduling.class_published?(slot),
        workout_status: Scheduling.class_workout_status(slot, now, zone)
      })
    end)
  end

  defp enrich_slots(slots, context, actor) do
    nickname_cache = booking_nickname_cache(slots, admin_role?(context, actor))

    variants =
      if admin_role?(context, actor),
        do: slots |> class_variants(context, actor) |> attach_assignee_nicknames(nickname_cache),
        else: class_variants(slots, context, actor)

    workout_cache =
      slots
      |> Enum.map(& &1.master_workout_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.reduce(%{}, fn workout_id, acc ->
        Map.put(acc, workout_id, Workouts.get_workout(context, workout_id))
      end)

    slot_ids = Enum.map(slots, & &1.id)

    # TD-105: the member's own check-in state on each class they booked.
    my_attendance = Scheduling.list_user_attendance(context, actor.id, slot_ids)

    # ADR-198: staff see everyone's on the roster (the coach's check-in desk).
    roster_attendance =
      if admin_role?(context, actor),
        do: Scheduling.list_class_attendance(context, slot_ids),
        else: %{}

    Enum.map(slots, fn slot ->
      workout = Map.get(workout_cache, slot.master_workout_id)
      current_booking = Enum.find(slot.bookings, &active_booking_for_user?(&1, actor.id))
      current_guest = Enum.find(slot.bookings, &active_guest_for_user?(&1, actor.id))

      waitlist =
        slot.bookings
        |> Enum.filter(&(&1.status == :waitlisted))
        |> BookingPolicy.waitlist_order()

      base = %{
        id: slot.id,
        master_workout_id: slot.master_workout_id,
        class_series_id: slot.class_series_id,
        class_series: slot.class_series,
        name: slot.name,
        duration_minutes: slot.duration_minutes,
        scheduled_at: slot.scheduled_at,
        class_type_id: slot.class_type_id,
        class_type: slot.class_type,
        capacity: slot.capacity,
        auto_approve: slot.auto_approve,
        booking_timeout_minutes: slot.booking_timeout_minutes,
        approved_booking_count: slot.approved_booking_count,
        spots_remaining: slot.spots_remaining,
        location_id: Map.get(slot, :location_id),
        coach_user_id: Map.get(slot, :coach_user_id),
        waitlist_count: length(waitlist),
        workout: preview_workout(workout),
        current_user_booking:
          current_booking &&
            current_booking
            |> enrich_booking(nickname_cache)
            |> Map.put(:waitlist_position, waitlist_position(waitlist, current_booking))
            |> Map.put(:attendance_status, Map.get(my_attendance, slot.id))
            |> Map.merge(check_in_window(slot)),
        current_user_guest: current_guest && enrich_booking(current_guest, nickname_cache)
      }

      if admin_role?(context, actor) do
        base
        |> Map.put(
          :bookings,
          Enum.map(slot.bookings, &roster_booking(&1, slot.id, nickname_cache, roster_attendance))
        )
        |> Map.put(:member_versions, staff_versions(variants, slot.id))
      else
        base
        |> Map.put(:bookings, [])
        |> Map.put(:raw_bookings, slot.bookings)
        |> Map.put(:my_version, my_version(variants, slot.id))
      end
    end)
  end

  # Phase 2 «μόνο ό,τι καλύπτει το πακέτο μου»: for members, whether their
  # package includes each class (scope only, not remaining visits).
  defp put_package_coverage(slots, context, actor) do
    if admin_role?(context, actor) do
      slots
    else
      requests =
        Enum.map(slots, fn slot ->
          slot
          |> BookingPolicy.entitlement_request()
          |> Map.merge(%{starts_at: slot.scheduled_at, location_id: slot.location_id})
        end)

      slots
      |> Enum.zip(Finance.package_coverage(context, actor.id, requests))
      |> Enum.map(fn {slot, covered?} -> Map.put(slot, :covered_by_package, covered?) end)
    end
  end

  # The class sheet's «ακύρωση χωρίς χρέωση έως» line: when withdrawing stops
  # being free for this member, from the same terms WithdrawBooking applies.
  defp put_cancel_free_until(slots, context, actor) do
    if admin_role?(context, actor) do
      slots
    else
      slots
      |> Enum.zip(BookingTerms.cancel_free_until(context, actor.id, slots))
      |> Enum.map(fn {slot, until} -> Map.put(slot, :cancel_free_until, until) end)
    end
  end

  # ADR-142 decision 12 (the «Φίλοι» chip): people the member follows who
  # share their bookings with followers and hold a place in the class. The
  # bookings are already loaded; only who shares comes from the account side.
  defp put_friends_going(slots, context, actor) do
    sharers =
      if admin_role?(context, actor),
        do: MapSet.new(),
        else: MapSet.new(Community.booking_sharer_ids(%{user_id: actor.id}))

    going =
      Map.new(slots, fn slot ->
        {slot.id,
         slot
         |> Map.get(:raw_bookings, [])
         |> Enum.filter(&friend_booking?(&1, sharers))
         |> Enum.map(& &1.user_id)
         |> Enum.uniq()}
      end)

    people =
      going
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(
        &{&1.id, %{id: &1.id, nickname: &1.nickname, avatar_url: Map.get(&1, :avatar_url)}}
      )

    Enum.map(slots, fn slot ->
      friends =
        going |> Map.get(slot.id, []) |> Enum.map(&Map.get(people, &1)) |> Enum.reject(&is_nil/1)

      slot
      |> Map.delete(:raw_bookings)
      |> Map.put(:friends_going, friends)
    end)
  end

  defp friend_booking?(booking, sharers),
    do:
      MapSet.member?(sharers, booking.user_id) and is_nil(Map.get(booking, :guest_name)) and
        booking.status in [:pending, :approved]

  # ADR-125: per-member class variants. A member only ever receives their own
  # variant (`assignee_id` = actor); staff receive every member's.
  defp class_variants(slots, context, actor) do
    slot_ids = Enum.map(slots, & &1.id)

    if admin_role?(context, actor) do
      Workouts.list_class_variants(context, slot_ids, nil)
    else
      Workouts.list_class_variants(context, slot_ids, actor.id)
    end
  end

  defp my_version(variants, slot_id) do
    case Enum.find(variants, &(&1.source_slot_id == slot_id)) do
      nil ->
        nil

      variant ->
        %{
          assignment_id: variant.assignment_id,
          master_workout_id: variant.master_workout_id,
          scheduled_for: variant.scheduled_for,
          status: variant.assignee_status,
          execution_status: Map.get(variant, :execution_status),
          # Same shape as a /my-workouts assignment workout.
          workout: variant.workout
        }
    end
  end

  defp staff_versions(variants, slot_id) do
    variants
    |> Enum.filter(&(&1.source_slot_id == slot_id))
    |> Enum.map(fn variant ->
      %{
        assignment_id: variant.assignment_id,
        user_id: variant.assignee_id,
        user_nickname: Map.get(variant, :assignee_nickname),
        master_workout_id: variant.master_workout_id,
        workout_title: variant.workout && variant.workout.title
      }
    end)
  end

  defp attach_assignee_nicknames(variants, nickname_cache) do
    missing =
      variants
      |> Enum.map(& &1.assignee_id)
      |> Enum.reject(&Map.has_key?(nickname_cache, &1))
      |> Enum.uniq()

    cache =
      missing
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})
      |> Map.merge(nickname_cache)

    Enum.map(variants, &Map.put(&1, :assignee_nickname, Map.get(cache, &1.assignee_id)))
  end

  defp admin_role?(context, _actor), do: context.role in [:owner, :admin, :coach]

  defp preview_workout(nil), do: nil

  defp preview_workout(workout) do
    %{
      id: workout.id,
      title: workout.title,
      type: workout.type,
      focus: Workouts.workout_focus(workout),
      sections:
        Enum.map(workout.sections || [], fn section ->
          %{
            id: section.id,
            name: section.name,
            order: section.order,
            scoreable: section.scoreable,
            score_config: section.score_config,
            timer_config: section.timer_config,
            exercises:
              Enum.map(section.exercises || [], fn exercise ->
                %{
                  id: exercise.id,
                  name: exercise.name,
                  sets: exercise.sets,
                  prescription_value: exercise.prescription_value,
                  prescription_unit: exercise.prescription_unit,
                  load_value: exercise.load_value,
                  load_mode: exercise.load_mode,
                  order: exercise.order,
                  superset_group_id: exercise.superset_group_id,
                  hr_zone: exercise.hr_zone,
                  tempo: exercise.tempo,
                  rest_seconds: exercise.rest_seconds,
                  cluster_rest_seconds: exercise.cluster_rest_seconds,
                  rest_pause_seconds: exercise.rest_pause_seconds,
                  pacing: exercise.pacing,
                  interval_assignment: exercise.interval_assignment,
                  variations:
                    Enum.map(exercise.variations || [], fn variation ->
                      exercise_name_override = Map.get(variation, :exercise_name_override)

                      %{
                        id: variation.id,
                        description: exercise_name_override,
                        exercise_name_override: exercise_name_override,
                        sets: variation.sets,
                        prescription_value: variation.prescription_value,
                        prescription_unit: variation.prescription_unit,
                        load_value: variation.load_value,
                        load_mode: variation.load_mode,
                        excluded: variation.excluded,
                        scale_level: %{
                          id: variation.scale_level && variation.scale_level.id,
                          slug: variation.scale_level && variation.scale_level.slug,
                          label: variation.scale_level && variation.scale_level.label,
                          sort_order: variation.scale_level && variation.scale_level.sort_order
                        }
                      }
                    end)
                }
              end)
          }
        end)
    }
  end

  defp check_in_window(slot) do
    {opens_at, closes_at} = Scheduling.self_check_in_window(slot)
    %{check_in_opens_at: opens_at, check_in_closes_at: closes_at}
  end

  defp enrich_booking(booking, nickname_cache) do
    %{
      id: booking.id,
      user_id: booking.user_id,
      user_nickname: Map.get(nickname_cache, booking.user_id),
      status: to_string(booking.status),
      guest_name: Map.get(booking, :guest_name),
      # ADR-144: the roster tags trial seats (board 6 Q4).
      kind: Map.get(booking, :kind, "member"),
      entitlement_allowance: Map.get(booking, :entitlement_allowance),
      waitlist_priority: Map.get(booking, :waitlist_priority),
      admin_message: booking.admin_message,
      inserted_at: booking.inserted_at
    }
  end

  # Attendance is per member and class; a guest seat has none of its own.
  defp roster_booking(booking, slot_id, nickname_cache, attendance) do
    status =
      if Map.get(booking, :guest_name),
        do: nil,
        else: attendance_status(attendance, slot_id, booking.user_id)

    booking
    |> enrich_booking(nickname_cache)
    |> Map.put(:attendance_status, status)
  end

  defp attendance_status(attendance, slot_id, user_id) do
    case Map.get(attendance, {slot_id, user_id}) do
      nil -> nil
      status -> to_string(status)
    end
  end

  # Takes the already-resolved decision rather than re-deriving it from the
  # global account role, which says nothing about this organization (F-29).
  defp booking_nickname_cache(slots, admin?) do
    if admin? do
      slots
      |> Enum.flat_map(& &1.bookings)
      |> Enum.map(& &1.user_id)
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})
    else
      %{}
    end
  end

  defp active_booking_for_user?(booking, user_id),
    do:
      booking.user_id == user_id and is_nil(Map.get(booking, :guest_name)) and
        booking.status in [:pending, :approved, :waitlisted]

  defp active_guest_for_user?(booking, user_id),
    do:
      booking.user_id == user_id and not is_nil(Map.get(booking, :guest_name)) and
        booking.status in [:pending, :approved, :waitlisted]

  defp waitlist_position(waitlist, %{status: :waitlisted, id: id}),
    do: Enum.find_index(waitlist, &(&1.id == id)) + 1

  defp waitlist_position(_waitlist, _booking), do: nil

  # Phase 2 Πρόγραμμα: the coaches of the window's classes, for the row and
  # the Coach filter, so members need no staff listing.
  defp schedule_coaches(slots) do
    slots
    |> Enum.map(&Map.get(&1, :coach_user_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Enum.map(&%{id: &1.id, nickname: &1.nickname, avatar_url: &1.avatar_url})
    |> Enum.sort_by(& &1.nickname)
  end

  defp schedule_class_types(context, slots) do
    active =
      Scheduling.list_class_types(context)

    referenced_archived =
      slots
      |> Enum.map(& &1.class_type)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&is_nil(&1.archived_at))

    (active ++ referenced_archived)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{&1.sort_order, &1.name})
  end

  defp normalize_window(params) do
    with {:ok, days} <- parse_days(params["days"] || params[:days]),
         {:ok, window} <- parse_explicit_window(params),
         {:ok, class_type_ids} <-
           parse_class_type_ids(params["class_type_ids"] || params[:class_type_ids]) do
      {:ok, window, days, class_type_ids}
    end
  end

  # Dates are read on the gym's clock: `nil` is the gym's today.
  defp window_bounds({:dates, nil}, days, zone),
    do: window_bounds({:dates, ZonedTime.local_date(DateTime.utc_now(), zone)}, days, zone)

  defp window_bounds({:dates, start_date}, days, zone),
    do:
      {ZonedTime.start_of_day(start_date, zone),
       ZonedTime.start_of_day(Date.add(start_date, days), zone)}

  defp window_bounds({:instants, start_at, end_at}, _days, _zone), do: {start_at, end_at}

  defp parse_explicit_window(params) do
    start_at_param = params["start_at"] || params[:start_at]
    end_at_param = params["end_at"] || params[:end_at]

    if is_nil(start_at_param) and is_nil(end_at_param) do
      with {:ok, start_date} <- parse_date(params["start_date"] || params[:start_date]) do
        {:ok, {:dates, start_date}}
      end
    else
      with {:ok, start_at} <- parse_datetime(start_at_param),
           {:ok, end_at} <- parse_datetime(end_at_param),
           :ok <- validate_window_order(start_at, end_at) do
        {:ok, {:instants, start_at, end_at}}
      end
    end
  end

  defp parse_date(nil), do: {:ok, nil}
  defp parse_date(%Date{} = value), do: {:ok, value}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, :bad_request}
    end
  end

  defp parse_days(nil), do: {:ok, 7}
  defp parse_days(value) when is_integer(value) and value in [3, 7, 30], do: {:ok, value}

  defp parse_days(value) when is_binary(value) do
    case Integer.parse(value) do
      {days, ""} when days in [3, 7, 30] -> {:ok, days}
      _ -> {:error, :bad_request}
    end
  end

  defp parse_days(_), do: {:error, :bad_request}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, :bad_request}
    end
  end

  defp parse_datetime(%DateTime{} = value), do: {:ok, value}

  defp parse_datetime(_), do: {:error, :bad_request}

  defp validate_window_order(start_at, end_at) do
    case DateTime.compare(end_at, start_at) do
      :gt -> :ok
      _ -> {:error, :bad_request}
    end
  end

  defp parse_class_type_ids(nil), do: {:ok, []}
  defp parse_class_type_ids(""), do: {:ok, []}

  defp parse_class_type_ids(value) do
    value
    |> List.wrap()
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, ids} ->
      case Ecto.UUID.cast(id) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | ids]}}
        :error -> {:halt, {:error, :bad_request}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids) |> Enum.uniq()}
      error -> error
    end
  end
end
