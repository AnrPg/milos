defmodule MilosTraining.Application.GetScheduleCalendar do
  alias MilosTraining.{Identity, Scheduling, Workouts}

  def call(actor, params) do
    with {:ok, start_at, end_at, days, class_type_ids} <- normalize_window(params) do
      slots =
        %{
          start_at: start_at,
          end_at: end_at,
          class_type_ids: class_type_ids
        }
        |> Scheduling.get_calendar_week()
        |> enrich_slots(actor)

      class_types = schedule_class_types(slots)

      {:ok,
       %{
         start_date: DateTime.to_date(start_at),
         end_date: DateTime.to_date(DateTime.add(end_at, -1, :second)),
         days: days,
         class_types: class_types,
         slots: slots
       }}
    end
  end

  defp enrich_slots(slots, actor) do
    nickname_cache = booking_nickname_cache(slots, actor)

    workout_cache =
      slots
      |> Enum.map(& &1.master_workout_id)
      |> Enum.uniq()
      |> Enum.reduce(%{}, fn workout_id, acc ->
        Map.put(acc, workout_id, Workouts.get_workout(workout_id))
      end)

    Enum.map(slots, fn slot ->
      workout = Map.get(workout_cache, slot.master_workout_id)
      current_booking = Enum.find(slot.bookings, &active_booking_for_user?(&1, actor.id))

      base = %{
        id: slot.id,
        master_workout_id: slot.master_workout_id,
        scheduled_at: slot.scheduled_at,
        class_type_id: slot.class_type_id,
        class_type: slot.class_type,
        capacity: slot.capacity,
        auto_approve: slot.auto_approve,
        booking_timeout_minutes: slot.booking_timeout_minutes,
        approved_booking_count: slot.approved_booking_count,
        spots_remaining: slot.spots_remaining,
        workout: preview_workout(workout),
        current_user_booking: current_booking && enrich_booking(current_booking, nickname_cache)
      }

      if actor.role == :admin do
        Map.put(base, :bookings, Enum.map(slot.bookings, &enrich_booking(&1, nickname_cache)))
      else
        Map.put(base, :bookings, [])
      end
    end)
  end

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
      admin_message: booking.admin_message,
      inserted_at: booking.inserted_at
    }
  end

  defp booking_nickname_cache(slots, actor) do
    if actor.role == :admin do
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
    do: booking.user_id == user_id and booking.status in [:pending, :approved]

  defp schedule_class_types(slots) do
    active = Scheduling.list_class_types()

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
      :error -> {:error, :bad_request}
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
