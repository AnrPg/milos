defmodule MilosTraining.Application.GetScheduleCalendar do
  alias MilosTraining.{Facility, Identity, Scheduling, Workouts}
  alias MilosTraining.Scheduling.Domain.BookingPolicy

  def call(context, actor, params) do
    with {:ok, start_at, end_at, days, class_type_ids} <- normalize_window(params) do
      slots =
        get_calendar_week(context, %{
          start_at: start_at,
          end_at: end_at,
          class_type_ids: class_type_ids
        })
        |> enrich_slots(context, actor)

      class_types = schedule_class_types(context, slots)

      {:ok,
       %{
         start_date: DateTime.to_date(start_at),
         end_date: DateTime.to_date(DateTime.add(end_at, -1, :second)),
         days: days,
         class_types: class_types,
         locations: Facility.list_locations(context, include_archived: true),
         slots: slots
       }}
    end
  end

  def call(_actor, _params), do: {:error, :organization_context_required}

  defp get_calendar_week(context, params), do: Scheduling.get_calendar_week(context, params)

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
            |> Map.put(:waitlist_position, waitlist_position(waitlist, current_booking)),
        current_user_guest: current_guest && enrich_booking(current_guest, nickname_cache)
      }

      if admin_role?(context, actor) do
        base
        |> Map.put(:bookings, Enum.map(slot.bookings, &enrich_booking(&1, nickname_cache)))
        |> Map.put(:member_versions, staff_versions(variants, slot.id))
      else
        base
        |> Map.put(:bookings, [])
        |> Map.put(:my_version, my_version(variants, slot.id))
      end
    end)
  end

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

  defp enrich_booking(booking, nickname_cache) do
    %{
      id: booking.id,
      user_id: booking.user_id,
      user_nickname: Map.get(nickname_cache, booking.user_id),
      status: to_string(booking.status),
      guest_name: Map.get(booking, :guest_name),
      entitlement_allowance: Map.get(booking, :entitlement_allowance),
      waitlist_priority: Map.get(booking, :waitlist_priority),
      admin_message: booking.admin_message,
      inserted_at: booking.inserted_at
    }
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
         {:ok, start_at, end_at} <- parse_explicit_window(params, days),
         {:ok, class_type_ids} <-
           parse_class_type_ids(params["class_type_ids"] || params[:class_type_ids]) do
      {:ok, start_at, end_at, days, class_type_ids}
    end
  end

  defp parse_explicit_window(params, days) do
    start_at_param = params["start_at"] || params[:start_at]
    end_at_param = params["end_at"] || params[:end_at]

    if is_nil(start_at_param) and is_nil(end_at_param) do
      with {:ok, start_date} <- parse_date(params["start_date"] || params[:start_date]) do
        start_at = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
        {:ok, start_at, DateTime.add(start_at, 86_400 * days, :second)}
      end
    else
      with {:ok, start_at} <- parse_datetime(start_at_param),
           {:ok, end_at} <- parse_datetime(end_at_param),
           :ok <- validate_window_order(start_at, end_at) do
        {:ok, start_at, end_at}
      end
    end
  end

  defp parse_date(nil), do: {:ok, Date.utc_today()}
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
