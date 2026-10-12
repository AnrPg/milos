defmodule MilosTraining.Application.GetTrainingLog do
  @moduledoc """
  One page of a user's training log, for their own profile and for the
  coach/admin view of their profile:

    * `"workouts"` – every workout they did or started (any source), newest
      first, each with the workout itself (sections, formats, exercises) and
      their performance on it (status, time, scale, section scores);
    * `"classes"` – the classes they booked and that already took place,
      newest first, each with the class's workout, their attendance and their
      performance on that class's workout, when they logged it.

  Paged with `offset`/`limit` so the UI can reveal history progressively.
  """

  alias MilosTraining.Execution
  alias MilosTraining.Execution.ExecutionStore
  alias MilosTraining.{Scheduling, Workouts}

  @default_limit 10
  @max_limit 50

  def call(context, user_id, params \\ %{}) do
    kind = param(params, "kind") || "workouts"
    limit = params |> param("limit") |> to_int(@default_limit) |> min(@max_limit) |> max(1)
    offset = params |> param("offset") |> to_int(0) |> max(0)

    case kind do
      "workouts" -> {:ok, workouts(context, user_id, limit, offset)}
      "classes" -> {:ok, classes(context, user_id, limit, offset)}
      _other -> {:error, :invalid_history_kind}
    end
  end

  ## Workouts

  defp workouts(context, user_id, limit, offset) do
    ExecutionStore.with_user_context(context, fn ->
      executions = Execution.list_executions_for_user(user_id)
      page = executions |> Enum.drop(offset) |> Enum.take(limit)
      workouts = load_workouts(context, Enum.map(page, & &1.master_workout_id))

      %{
        kind: "workouts",
        total: length(executions),
        offset: offset,
        next_offset: next_offset(offset, limit, length(executions)),
        entries:
          Enum.map(page, fn execution ->
            workout = Map.get(workouts, execution.master_workout_id)

            %{
              id: execution.id,
              occurred_at: execution.started_at_utc,
              source: to_string(execution.source),
              workout: workout_summary(workout),
              performance: performance(execution, workout)
            }
          end)
      }
    end)
  end

  ## Classes

  defp classes(context, user_id, limit, offset) do
    %{entries: bookings, total: total} =
      Scheduling.list_class_history(context, user_id, %{limit: limit, offset: offset})

    booking_ids = MapSet.new(bookings, & &1.booking_id)

    executions =
      ExecutionStore.with_user_context(context, fn ->
        user_id
        |> Execution.list_executions_for_user()
        |> Enum.filter(&(to_string(&1.source) == "class_booking"))
        |> Enum.filter(&MapSet.member?(booking_ids, &1.source_reference_id))
        # Newest first: keep the latest attempt per booking.
        |> Enum.reduce(%{}, fn execution, acc ->
          Map.put_new(acc, execution.source_reference_id, execution)
        end)
      end)

    workouts = load_workouts(context, Enum.map(bookings, & &1.master_workout_id))

    %{
      kind: "classes",
      total: total,
      offset: offset,
      next_offset: next_offset(offset, limit, total),
      entries:
        Enum.map(bookings, fn booking ->
          workout = Map.get(workouts, booking.master_workout_id)
          execution = Map.get(executions, booking.booking_id)

          %{
            id: booking.booking_id,
            occurred_at: booking.scheduled_at,
            class: %{
              name: booking.class_name,
              type_name: booking.class_type_name,
              duration_minutes: booking.duration_minutes,
              attendance: booking.attendance_status
            },
            workout: workout_summary(workout),
            performance: execution && performance(execution, workout)
          }
        end)
    }
  end

  ## Shared

  defp load_workouts(context, ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Map.new(&{&1, Workouts.get_workout(context, &1)})
  end

  defp workout_summary(nil), do: nil

  defp workout_summary(workout) do
    %{
      id: workout.id,
      title: workout.title,
      type: workout.type && to_string(workout.type),
      sections:
        Enum.map(workout.sections || [], fn section ->
          %{
            id: section.id,
            name: section.name,
            nested: not is_nil(section.parent_section_id),
            format: format(section.timer_config),
            timer_config: section.timer_config,
            score_type: score_type(section),
            exercises:
              Enum.map(section.exercises || [], fn exercise ->
                exercise
                |> Map.take([
                  :name,
                  :sets,
                  :prescription_value,
                  :prescription_unit,
                  :load_value,
                  :load_mode,
                  :interval_assignment
                ])
              end)
          }
        end)
    }
  end

  defp performance(execution, workout) do
    sections = if workout, do: Map.new(workout.sections || [], &{&1.id, &1}), else: %{}

    %{
      execution_id: execution.id,
      status: to_string(execution.status),
      started_at: execution.started_at_utc,
      completed_at: execution.completed_at_utc,
      elapsed_ms: execution.total_elapsed_ms,
      scale_level_slug: execution.scale_level_slug,
      scores:
        Enum.map(execution.section_scores || [], fn score ->
          section_id = field(score, :section_id)
          section = Map.get(sections, section_id)

          %{
            section_id: section_id,
            section_name: section && section.name,
            score_type: section && score_type(section),
            value: field(score, :value),
            unit: field(score, :unit)
          }
        end)
    }
  end

  defp format(%{} = config), do: to_string(config[:type] || config["type"] || "untimed")
  defp format(_config), do: "untimed"

  defp score_type(%{score_config: %{} = config}),
    do: (config[:type] || config["type"]) && to_string(config[:type] || config["type"])

  defp score_type(_section), do: nil

  defp next_offset(offset, limit, total) when offset + limit < total, do: offset + limit
  defp next_offset(_offset, _limit, _total), do: nil

  defp param(params, key), do: Map.get(params, key) || Map.get(params, String.to_atom(key))

  defp to_int(nil, default), do: default
  defp to_int(value, _default) when is_integer(value), do: value

  defp to_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> default
    end
  end

  defp to_int(_value, default), do: default

  defp field(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
