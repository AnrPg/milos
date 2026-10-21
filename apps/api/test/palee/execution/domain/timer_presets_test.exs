defmodule Palee.Execution.Domain.TimerPresetsTest do
  @moduledoc """
  The web app builds the same segments from a preset
  (`apps/web/src/lib/free-text-timer.ts`). Both sides check the shared
  fixture `apps/web/src/lib/timer-preset-fixtures.json`, so the class timer's
  server-side catch-up and every screen agree.
  """
  use ExUnit.Case, async: true

  alias Palee.Execution.Domain.TimerPresets

  @fixture_path Path.expand("../../../../../web/src/lib/timer-preset-fixtures.json", __DIR__)
  @external_resource @fixture_path
  @fixture @fixture_path |> File.read!() |> Jason.decode!()

  for %{"preset" => preset, "segments" => expected} <- @fixture["cases"] do
    @preset preset
    @expected expected

    test "builds #{preset["format"]} like the web app" do
      segments = @preset |> TimerPresets.parse() |> TimerPresets.build()

      assert Enum.map(
               segments,
               &[to_string(&1.kind), &1.phase, &1.duration_seconds, &1.total_rounds]
             ) ==
               @expected
    end
  end

  test "rejects unknown formats and keeps only positive numbers" do
    assert TimerPresets.parse(%{"format" => "bogus"}) == nil

    assert %{"duration_seconds" => nil} =
             TimerPresets.parse(%{"format" => "amrap", "duration_seconds" => -3})
  end
end
