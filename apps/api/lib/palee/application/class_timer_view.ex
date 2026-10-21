defmodule Palee.Application.ClassTimerView do
  @moduledoc """
  Loads a scheduled class with its timer and the segments the timer runs, and
  shapes the payload every screen (wall display, coach remote, member phone)
  renders. `server_now` lets clients correct for their own clock being off.
  """

  alias Palee.{Execution, Scheduling, Workouts}
  alias Palee.Execution.Domain.{ClassTimerMachine, DurationAdjustments, TimerPresets}

  @free_text_timer_key "free_text_timer"

  @doc "Returns `{:ok, %{slot, workout, timer, base_segments}}` or `{:error, :not_found}`."
  def load(context, slot_id) do
    with {:ok, slot_id} <- Ecto.UUID.cast(slot_id),
         %{} = slot <- Scheduling.get_slot(context, slot_id) do
      workout = slot.master_workout_id && Workouts.get_workout(context, slot.master_workout_id)
      timer = Execution.get_class_timer(context, slot_id)

      {:ok,
       %{
         slot: slot,
         workout: workout,
         timer: timer,
         base_segments: base_segments(workout, timer)
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Replaces the timer (after a save); its preset may change the segments."
  def with_timer(view, timer),
    do: %{view | timer: timer, base_segments: base_segments(view.workout, timer)}

  @doc "The timer as stored (or a fresh one), in machine form."
  def state(nil), do: ClassTimerMachine.initial()

  def state(timer) do
    %{
      status: timer.status,
      current_segment_index: timer.current_segment_index,
      segment_started_at_utc: timer.segment_started_at_utc,
      paused_elapsed_ms: timer.paused_elapsed_ms,
      duration_adjustments: timer.duration_adjustments || %{}
    }
  end

  def payload(%{slot: slot, workout: workout, timer: timer, base_segments: base}, now) do
    state = state(timer)
    segments = DurationAdjustments.apply_to(base, state.duration_adjustments)
    effective = ClassTimerMachine.catch_up(state, segments, now)

    %{
      class: %{
        id: slot.id,
        name: slot.name,
        scheduled_at: slot.scheduled_at,
        duration_minutes: slot.duration_minutes
      },
      workout:
        workout &&
          %{
            id: workout.id,
            title: workout.title,
            authoring_mode: Map.get(workout, :authoring_mode),
            free_text_body: Map.get(workout, :free_text_body)
          },
      segments: segments,
      timer:
        effective
        |> Map.merge(%{
          lock_version: (timer && timer.lock_version) || 1,
          timer_preset: timer && timer.timer_preset,
          updated_at: timer && timer.updated_at
        }),
      server_now: now
    }
  end

  # A timer the coach picked for this class wins (e.g. an EMOM clock for an
  # untimed strength class). Otherwise structured workouts run their own
  # sequence, and free-text ones the preset attached to the workout.
  defp base_segments(workout, timer) do
    case TimerPresets.parse(timer && timer.timer_preset) do
      %{} = preset ->
        TimerPresets.build(preset)

      nil ->
        structured =
          if workout && Map.get(workout, :authoring_mode) != "free_text",
            do: Execution.build_timer_sequence(workout),
            else: []

        case {structured, TimerPresets.parse(workout_preset(workout))} do
          {[_ | _], _preset} -> structured
          {[], %{} = preset} -> TimerPresets.build(preset)
          {[], nil} -> []
        end
    end
  end

  defp workout_preset(nil), do: nil

  defp workout_preset(workout) do
    case Map.get(workout, :workout_metadata) do
      %{} = metadata -> Map.get(metadata, @free_text_timer_key)
      _ -> nil
    end
  end
end
