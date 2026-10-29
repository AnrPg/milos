defmodule Palee.Workouts.Domain.StructuredPlan.PrescriptionTest do
  use ExUnit.Case, async: true

  import Palee.StructuredPlanFixtures

  alias Palee.Workouts.Domain.StructuredPlan.Prescription

  defp build(index), do: Prescription.build(Enum.at(program(), index))
  defp row(section, id), do: Enum.find(section.rows, &(&1.row_id == id))
  defp loads(row), do: Enum.map(row.sets, &(&1.load && &1.load.value))
  defp reps(row), do: Enum.map(row.sets, &(&1.reps && &1.reps.min))
  defp d(value), do: Decimal.new(value)

  test "a sets flow: one set per column, loads progress with the unit written once" do
    section = build(0)

    assert %{flow: "sets", sets: %{min: 4, max: 4}, rest_secs: %{min: 120, max: 120}} =
             section.clock

    assert section.clock.total_rounds == 4
    refute section.clock.open_ended

    squat = row(section, "r1")
    assert reps(squat) == [12, 10, 8, 8]
    assert loads(squat) == [d(60), d(65), d(70), d(75)]
    assert Enum.all?(squat.sets, &(&1.load.kind == "pct_1rm"))
    assert Enum.map(squat.sets, & &1.rounds) == [[1], [2], [3], [4]]
    assert hd(squat.sets).measures.tempo == %{down: 3, bottom: 1, up: "X", top: 1}
    assert squat.then == nil
  end

  test "spread loads, decimals and per-side doses" do
    bench = row(build(15), "r30")
    assert loads(bench) == [d(60), d("66.7"), d("73.3"), d(80)]

    bulgarian = row(build(13), "r28")
    assert bulgarian.per_side
    assert %{min: 8, max: 10, unit: "reps"} = hd(bulgarian.sets).reps
    assert %{kind: "kg", value: value} = hd(bulgarian.sets).load
    assert Decimal.equal?(value, d("22.5"))
    assert hd(bulgarian.sets).measures.rpe == 8
    assert build(13).clock.rest_secs == %{min: 90, max: 120}
  end

  test "groups, structures, rest rows, words and max effort" do
    superset = build(1)
    assert Enum.map(superset.rows, & &1.group_id) == ["g1", "g1", "g1"]
    assert Enum.all?(superset.rows, &(&1.structure.kind == "superset"))

    giant = build(2)
    assert Enum.map(row(giant, "r6").sets, & &1.rest_secs) == [30, 30, 30, 30]
    assert row(giant, "r6").kind == "rest"

    assert Enum.all?(
             row(giant, "r5").sets,
             &(&1.load == %{kind: "qualitative", value: nil, value_max: nil, text: "με βάρος"})
           )

    assert %{unit: "kcal", max_effort: true, within_secs: 60} = hd(row(giant, "r9").sets).reps

    assert %{kind: "cluster", clusters: 3, intra_secs: 15} = row(build(3), "r10").structure
  end

  test "blocks alternate rounds; same-every-time rows are one set over their rounds" do
    even_odd = build(5)
    assert hd(row(even_odd, "r13").sets).rounds == [1, 3, 5, 7]
    assert hd(row(even_odd, "r14").sets).rounds == [2, 4, 6, 8]
    assert row(even_odd, "r14").block_index == 1

    chipper = build(8)
    assert %{min: 500, unit: "meters"} = hd(row(chipper, "r19").sets).reps
    assert hd(row(chipper, "r21").sets).rounds == [2, 4]
  end

  test "interruptions: block -1, every interruption" do
    section = build(7)
    assert section.clock.interrupt_every_secs == 120
    burpee = row(section, "r18")
    assert %{block_index: -1, interrupt: true} = burpee
    assert [%{rounds: [], reps: %{min: 10}}] = burpee.sets
  end

  test "open-ended flows carry the written rounds and a then rule, never a count" do
    amrap = build(6)
    assert %{open_ended: true, total_rounds: nil, windows_secs: [420]} = amrap.clock

    snatch = row(amrap, "r16")
    assert reps(snatch) == [5, 10, 15]
    assert loads(snatch) == [d(40), d(45), d(50)]
    assert snatch.then == %{rule: "step", reps_step: nil, load_step: d(5)}
    assert row(amrap, "r15").then == %{rule: "repeat", reps_step: nil, load_step: nil}

    assert build(9).clock.windows_secs == [180, 180, 180, 240]
    assert reps(row(build(12), "r27")) == [5, 10, 15]
    assert row(build(12), "r27").then.reps_step == 5

    death_by =
      section("emom", %{"every" => "1:00", "times" => ""}, [[ex("d", "Burpee", "1-2-3…")]], %{
        "preset" => "death_by",
        "score" => "rounds_reps"
      })
      |> Prescription.build()

    assert %{open_ended: true, total_rounds: nil, every_secs: 60} = death_by.clock
    burpee = hd(death_by.rows)
    assert Enum.map(burpee.sets, & &1.rounds) == [[1], [2], [3]]
    assert burpee.then == %{rule: "step", reps_step: 1, load_step: nil}
  end

  test "canonical measures" do
    plan =
      section("sets", %{"sets" => "3"}, [
        [
          ex("m", "Row", "", "", %{
            "extra" => ["pace", "hold", "dist", "height", "zone", "rir"],
            "cells" => [
              %{
                "d" => "1",
                "pace" => "2:00/km",
                "hold" => "0:30",
                "dist" => "2 km",
                "height" => "1.2 m",
                "zone" => "z2",
                "rir" => "2"
              },
              %{"pace" => "-0:05", "hold" => "+5"},
              %{}
            ]
          })
        ]
      ])

    [one, two, three] = hd(Prescription.build(plan).rows).sets

    assert one.measures == %{
             pace_secs_per_500m: 60,
             hold_secs: 30,
             distance_m: 2000,
             height_cm: 120,
             hr_zone: 2,
             rir: 2,
             rpe: nil,
             tempo: nil
           }

    assert {two.measures.pace_secs_per_500m, two.measures.hold_secs} == {57.5, 35}
    assert {three.measures.pace_secs_per_500m, three.measures.hold_secs} == {55, 40}
  end

  test "a rest section has no rows; JSON turns decimals into numbers" do
    assert %{rows: [], clock: %{flow: "rest", dur_secs: 120}} = build(11)
    json = Prescription.to_json(build(15))
    assert [60, 66.7, 73.3, 80] == Enum.map(hd(json.rows).sets, & &1.load.value)
    assert Prescription.build(%{"flow" => "yoga"}) == nil
  end
end
