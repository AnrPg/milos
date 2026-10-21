defmodule Palee.Execution.Domain.ClassTimerMachine do
  @moduledoc """
  State machine for a coach-run class timer (the gym's wall display).

  The state is a schedule, not a ticking clock: the current segment, when it
  started (possibly in the future, during the get-ready countdown) and the
  time banked by pauses. Every screen derives the same clock from it, so a
  timed segment ending needs no write — clients and this module both "catch
  up" through segments that ran out (`catch_up/3` mirrors `planCatchUp` in
  `apps/web/src/lib/timer-engine.ts`). Only the coach's commands change state.

  `now` is always passed in; the module never reads the clock.
  """

  alias Palee.Execution.Domain.DurationAdjustments

  @get_ready_ms 10_000
  @resume_countdown_ms 3_000
  @max_countdown_seconds 60

  @type state :: %{
          status: String.t(),
          current_segment_index: non_neg_integer(),
          segment_started_at_utc: DateTime.t() | nil,
          paused_elapsed_ms: non_neg_integer(),
          duration_adjustments: map()
        }

  def initial,
    do: %{
      status: "ready",
      current_segment_index: 0,
      segment_started_at_utc: nil,
      paused_elapsed_ms: 0,
      duration_adjustments: %{}
    }

  @doc "How long a segment runs on its own; nil when only a person can end it."
  def segment_limit_ms(segment) do
    duration = positive(value(segment, :duration_seconds))

    case to_string(value(segment, :kind)) do
      kind when kind in ["countdown", "countup"] ->
        duration && duration * 1000

      "interval_cycle" ->
        lengths = window_lengths_ms(segment)
        windows = positive(value(segment, :total_rounds))

        if windows && lengths != [] do
          lengths |> Stream.cycle() |> Enum.take(windows) |> Enum.sum()
        end

      _ ->
        nil
    end
  end

  defp window_lengths_ms(segment) do
    pattern =
      case value(segment, :timer_config) do
        %{} = config -> value(config, :interval_pattern_seconds)
        _ -> nil
      end

    case pattern do
      [_ | _] = pattern ->
        lengths = pattern |> Enum.map(&positive/1) |> Enum.reject(&is_nil/1)
        if lengths != [], do: Enum.map(lengths, &(&1 * 1000)), else: fallback_window(segment)

      _ ->
        fallback_window(segment)
    end
  end

  defp fallback_window(segment) do
    case positive(value(segment, :duration_seconds)) do
      nil -> []
      seconds -> [seconds * 1000]
    end
  end

  @doc "Elapsed time in the current segment at `now`."
  def elapsed_ms(
        %{status: "running", segment_started_at_utc: %DateTime{} = started} = state,
        now
      ),
      do: state.paused_elapsed_ms + max(0, DateTime.diff(now, started, :millisecond))

  def elapsed_ms(state, _now), do: state.paused_elapsed_ms

  @doc """
  Moves past every timed segment that has already run out, starting each next
  one when the previous ended. The last segment finishes the timer.
  """
  def catch_up(%{status: "running", segment_started_at_utc: %DateTime{}} = state, segments, now) do
    last = length(segments) - 1
    segment = Enum.at(segments, state.current_segment_index)
    limit = segment && segment_limit_ms(segment)
    elapsed = elapsed_ms(state, now)

    cond do
      is_nil(limit) or elapsed < limit ->
        state

      state.current_segment_index >= last ->
        %{state | status: "finished", segment_started_at_utc: nil, paused_elapsed_ms: limit}

      true ->
        # The next segment starts exactly when this one ended.
        ended_at =
          DateTime.add(
            state.segment_started_at_utc,
            limit - state.paused_elapsed_ms,
            :millisecond
          )

        catch_up(
          %{
            state
            | current_segment_index: state.current_segment_index + 1,
              segment_started_at_utc: ended_at,
              paused_elapsed_ms: 0
          },
          segments,
          now
        )
    end
  end

  def catch_up(state, _segments, _now), do: state

  @doc """
  Applies a coach command. `base_segments` are the authored segments; clock
  adjustments in the state are applied here. Returns `{:ok, state}` or
  `{:error, reason}`.
  """
  def apply_command(state, command, params, base_segments, now) do
    segments = DurationAdjustments.apply_to(base_segments, state.duration_adjustments)
    state = catch_up(state, segments, now)
    command(command, state, params || %{}, segments, base_segments, now)
  end

  defp command(_command, _state, _params, [], _base, _now), do: {:error, :no_segments}

  defp command("start", state, params, _segments, _base, now)
       when state.status in ["ready", "finished"] do
    countdown = countdown_ms(params)

    {:ok,
     %{
       state
       | status: "running",
         current_segment_index: 0,
         segment_started_at_utc: DateTime.add(now, countdown, :millisecond),
         paused_elapsed_ms: 0
     }}
  end

  defp command("pause", %{status: "running"} = state, _params, _segments, _base, now) do
    {:ok,
     %{
       state
       | status: "paused",
         segment_started_at_utc: nil,
         paused_elapsed_ms: elapsed_ms(state, now)
     }}
  end

  defp command("resume", %{status: "paused"} = state, _params, _segments, _base, now) do
    {:ok,
     %{
       state
       | status: "running",
         segment_started_at_utc: DateTime.add(now, @resume_countdown_ms, :millisecond)
     }}
  end

  defp command("next", state, _params, segments, _base, now)
       when state.status in ["running", "paused"],
       do: {:ok, move_to(state, state.current_segment_index + 1, segments, now)}

  defp command("previous", state, _params, segments, _base, now)
       when state.status in ["running", "paused", "finished"] do
    state = if state.status == "finished", do: %{state | status: "paused"}, else: state
    {:ok, move_to(state, max(state.current_segment_index - 1, 0), segments, now)}
  end

  defp command("jump", state, params, segments, _base, now)
       when state.status in ["running", "paused", "ready", "finished"] do
    case value(params, :index) do
      index when is_integer(index) and index >= 0 ->
        if index < length(segments) do
          state =
            if state.status in ["ready", "finished"],
              do: %{state | status: "paused"},
              else: state

          {:ok, move_to(state, index, segments, now)}
        else
          {:error, :invalid_command}
        end

      _ ->
        {:error, :invalid_command}
    end
  end

  defp command("adjust", state, params, segments, base_segments, now) do
    with delta when is_integer(delta) and delta != 0 <- value(params, :delta_seconds),
         %{} = base <- Enum.at(base_segments, state.current_segment_index),
         %{} = current <- Enum.at(segments, state.current_segment_index),
         authored when is_integer(authored) <- positive(value(base, :duration_seconds)),
         true <- to_string(value(base, :kind)) in ["countdown", "countup"] do
      ran_seconds = div(elapsed_ms(state, now), 1000) + 1
      wanted = max(value(current, :duration_seconds) + delta, ran_seconds)
      key = to_string(value(base, :segment_key))

      existing =
        state.duration_adjustments
        |> Enum.map(fn {k, v} -> {to_string(k), delta_of(v)} end)
        |> Map.new()

      adjustments =
        existing
        |> Map.put(key, wanted - authored)
        |> Enum.reject(fn {_key, delta} -> delta == 0 end)
        |> Map.new()

      {:ok,
       %{
         state
         | duration_adjustments: DurationAdjustments.normalize(adjustments, base_segments, %{})
       }}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp command("reset", _state, _params, _segments, _base, _now), do: {:ok, initial()}

  defp command("finish", state, _params, _segments, _base, now)
       when state.status in ["running", "paused"],
       do:
         {:ok,
          %{
            state
            | status: "finished",
              segment_started_at_utc: nil,
              paused_elapsed_ms: elapsed_ms(state, now)
          }}

  defp command(command, _state, _params, _segments, _base, _now)
       when command in ~w(start pause resume next previous jump finish),
       do: {:error, :invalid_transition}

  defp command(_command, _state, _params, _segments, _base, _now), do: {:error, :invalid_command}

  defp move_to(state, index, segments, now) do
    if index >= length(segments) do
      %{state | status: "finished", segment_started_at_utc: nil, paused_elapsed_ms: 0}
    else
      %{
        state
        | current_segment_index: index,
          segment_started_at_utc: if(state.status == "running", do: now),
          paused_elapsed_ms: 0
      }
    end
  end

  defp countdown_ms(params) do
    case value(params, :countdown_seconds) do
      seconds when is_integer(seconds) and seconds >= 0 ->
        min(seconds, @max_countdown_seconds) * 1000

      _ ->
        @get_ready_ms
    end
  end

  defp delta_of(%{} = adjustment), do: value(adjustment, :delta_seconds) || 0
  defp delta_of(delta) when is_integer(delta), do: delta
  defp delta_of(_value), do: 0

  defp positive(value) when is_integer(value) and value > 0, do: value
  defp positive(_value), do: nil

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp value(_map, _key), do: nil
end
