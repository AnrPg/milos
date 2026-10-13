defmodule MilosTraining.Execution.Domain.ClassTimerMachineTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Execution.Domain.{ClassTimerMachine, TimerPresets}

  @t0 ~U[2026-10-12 18:00:00.000000Z]

  defp at(seconds), do: DateTime.add(@t0, seconds * 1000, :millisecond)

  defp segments do
    TimerPresets.build(%{
      "format" => "tabata",
      "work_seconds" => 20,
      "rest_seconds" => 10,
      "rounds" => 2
    })
  end

  defp run(state, command, now, params \\ %{}) do
    {:ok, state} = ClassTimerMachine.apply_command(state, command, params, segments(), now)
    state
  end

  test "start schedules the first segment after the get-ready countdown" do
    state = run(ClassTimerMachine.initial(), "start", @t0)

    assert state.status == "running"
    assert state.segment_started_at_utc == at(10)
    assert ClassTimerMachine.elapsed_ms(state, at(5)) == 0
  end

  test "catches up through segments that ran out, on schedule" do
    state = run(ClassTimerMachine.initial(), "start", @t0, %{"countdown_seconds" => 0})

    # 20 s work + 10 s rest + 5 s into work 2
    caught = ClassTimerMachine.catch_up(state, segments(), at(35))
    assert caught.current_segment_index == 2
    assert caught.segment_started_at_utc == at(30)
    assert ClassTimerMachine.elapsed_ms(caught, at(35)) == 5_000

    finished = ClassTimerMachine.catch_up(state, segments(), at(120))
    assert finished.status == "finished"
  end

  test "pause banks elapsed time and resume restarts after a short countdown" do
    state = run(ClassTimerMachine.initial(), "start", @t0, %{"countdown_seconds" => 0})
    paused = run(state, "pause", at(8))

    assert paused.status == "paused"
    assert paused.paused_elapsed_ms == 8_000

    resumed = run(paused, "resume", at(60))
    assert resumed.segment_started_at_utc == at(63)
    assert ClassTimerMachine.elapsed_ms(resumed, at(65)) == 10_000
  end

  test "navigation moves between segments and past the end finishes" do
    state = run(ClassTimerMachine.initial(), "start", @t0, %{"countdown_seconds" => 0})
    state = run(state, "next", at(3))
    assert state.current_segment_index == 1
    assert state.segment_started_at_utc == at(3)

    state = run(state, "previous", at(4))
    assert state.current_segment_index == 0

    state = run(state, "jump", at(5), %{"index" => 2})
    assert state.current_segment_index == 2

    assert run(state, "next", at(6)).status == "finished"
  end

  test "adjust lengthens the running segment but never below what already ran" do
    state = run(ClassTimerMachine.initial(), "start", @t0, %{"countdown_seconds" => 0})
    longer = run(state, "adjust", at(5), %{"delta_seconds" => 30})
    assert longer.duration_adjustments["free-text:0"]["delta_seconds"] == 30

    shorter = run(longer, "adjust", at(15), %{"delta_seconds" => -45})
    # 15 s already ran: the work interval can't end before 16 s.
    assert shorter.duration_adjustments["free-text:0"]["delta_seconds"] == 16 - 20
  end

  test "rejects commands that make no sense in the current state" do
    assert {:error, :invalid_transition} =
             ClassTimerMachine.apply_command(
               ClassTimerMachine.initial(),
               "pause",
               %{},
               segments(),
               @t0
             )

    assert {:error, :invalid_command} =
             ClassTimerMachine.apply_command(
               ClassTimerMachine.initial(),
               "explode",
               %{},
               segments(),
               @t0
             )

    assert {:error, :no_segments} =
             ClassTimerMachine.apply_command(ClassTimerMachine.initial(), "start", %{}, [], @t0)
  end

  test "segment limits match the client engine for interval cycles" do
    [emom] = TimerPresets.build(%{"format" => "emom", "interval_seconds" => 60, "rounds" => 10})
    assert ClassTimerMachine.segment_limit_ms(emom) == 600_000

    [death_by] = TimerPresets.build(%{"format" => "death_by"})
    assert ClassTimerMachine.segment_limit_ms(death_by) == nil
  end
end
