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

  test "ADR-179: chains each text section's timer, keyed and named by its section" do
    segments =
      TimerPresets.build_sections([
        %{
          id: "a",
          name: "Strength",
          timer_preset: %{"format" => "amrap", "duration_seconds" => 300}
        },
        %{id: "b", name: "Skip me", timer_preset: nil},
        %{"id" => "c", "name" => "Finisher", "timer_preset" => %{"format" => "tabata"}}
      ])

    assert [%{section_id: "a", section_name: "Strength", segment_key: "text-section:0:0"} | rest] =
             segments

    assert length(rest) == 15
    assert Enum.all?(rest, &(&1.section_id == "c" and &1.section_name == "Finisher"))
    assert segments |> Enum.map(& &1.segment_key) |> Enum.uniq() |> length() == 16
  end
end
