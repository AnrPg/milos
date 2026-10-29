defmodule Palee.Workouts.Domain.StructuredPlanTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.StructuredPlan
  alias Palee.Workouts.Domain.StructuredPlan.Notation

  import Palee.StructuredPlanFixtures

  defp codes(plan) do
    case StructuredPlan.validate(plan) do
      :ok -> []
      {:error, errors} -> Enum.map(errors, &{&1.path, &1.code})
    end
  end

  describe "valid plans" do
    test "every section of the reference program reads" do
      for plan <- program() do
        assert StructuredPlan.validate(plan) == :ok, inspect({plan["flow"], codes(plan)})
      end
    end

    test "decimals, words, +x and a→b loads, ranges and per-side doses read" do
      row =
        ex("a", "Lunge", "", "", %{
          "extra" => ["rpe", "side", "hold", "pace"],
          "cells" => [
            %{
              "d" => "8-12/πλευρά",
              "l" => "22.5 kg",
              "rpe" => "7",
              "hold" => "3",
              "pace" => "2:00"
            },
            %{"d" => "10 each side", "l" => "+2,5", "rpe" => "+1"},
            %{"d" => "", "l" => "60→80", "rpe" => "8→10"},
            %{"d" => "4×10", "l" => "βαρύ"},
            %{"d" => "+2", "l" => "25 κιλά"}
          ]
        })

      assert codes(section("sets", %{"sets" => "5"}, [[row]])) == []
    end

    test "unknown keys outside the contract are left out of the kept plan" do
      plan =
        section("for_time", %{"rounds" => "3"}, [[ex("a", "Run", "400 m", "", %{"ui" => true})]])
        |> Map.put("draftOnly", 1)

      assert {:ok, kept} = StructuredPlan.normalize(plan)
      refute Map.has_key?(kept, "draftOnly")
      refute kept |> get_in(["blocks", Access.at(0), Access.at(0)]) |> Map.has_key?("ui")
    end

    test "rows and units: groups of consecutive rows run together" do
      [_one, superset | _rest] = program()
      assert [%{group: "g1", rows: [_, _, _]}] = StructuredPlan.units(hd(superset["blocks"]))
      assert length(StructuredPlan.rows(Enum.at(program(), 7))) == 2
      assert StructuredPlan.exercise_count(Enum.at(program(), 2)) == 3
    end
  end

  describe "errors" do
    test "not a map, a wrong version and an unknown flow" do
      assert codes("plan") == [{"", "invalid"}]

      assert codes(%{"v" => 2, "flow" => "crossfit"}) == [
               {"v", "unsupported_version"},
               {"flow", "unknown_flow"}
             ]
    end

    test "params read per flow" do
      plan =
        section(
          "sets",
          %{"sets" => "four", "rest" => "soon", "cap" => "anything", "bogus" => "1"},
          []
        )

      assert codes(plan) == [
               {"params.bogus", "unknown_param"},
               {"params.rest", "bad_param"},
               {"params.sets", "bad_param"}
             ]

      assert codes(section("amrap", %{"dur" => "3-x-3"}, [])) == [{"params.dur", "bad_param"}]

      assert codes(section("emom", %{"every" => "1:00", "times" => "1.5"}, [])) == [
               {"params.times", "bad_param"}
             ]

      assert codes(section("intervals", %{"work" => "20″", "rounds" => 8}, [])) == [
               {"params.rounds", "invalid"}
             ]

      assert codes(section("rest", %{"dur" => String.duplicate("1", 201)}, [])) == [
               {"params.dur", "too_long"}
             ]

      assert codes(Map.delete(section("rest", %{}, []), "params")) == [{"params", "invalid"}]
    end

    test "add-on params are read only when the add-on is on" do
      on = section("for_time", %{"intEvery" => "soon"}, [], %{"mods" => %{"interrupt" => true}})
      assert codes(on) == [{"params.intEvery", "bad_param"}]
      assert codes(Map.delete(on, "mods")) == []
    end

    test "add-ons only where the flow allows them" do
      assert codes(section("sets", %{}, [], %{"mods" => %{"hr" => true}})) == [
               {"mods.hr", "mod_not_allowed"}
             ]

      assert codes(section("emom", %{}, [], %{"mods" => %{"hr" => false, "wow" => true}})) == [
               {"mods.wow", "unknown_mod"}
             ]

      assert codes(section("emom", %{}, [], %{"mods" => %{"hr" => "yes"}})) == [
               {"mods.hr", "invalid"}
             ]
    end

    test "structures only where the flow allows them, with fields that read" do
      assert codes(section("for_time", %{}, [], %{"structs" => %{"a" => %{"kind" => "cluster"}}})) ==
               [{"structs.a.kind", "struct_not_allowed"}]

      assert codes(section("sets", %{}, [], %{"structs" => %{"a" => %{"kind" => "giant"}}})) ==
               [{"structs.a.kind", "unknown_struct"}]

      bad = %{"kind" => "restpause", "minis" => "three", "intra" => "15″"}

      assert codes(section("sets", %{}, [], %{"structs" => %{"a" => bad}})) == [
               {"structs.a.minis", "bad_param"}
             ]

      assert codes(section("rest", %{}, [], %{"structs" => %{"a" => "single"}})) == [
               {"structs.a", "invalid"}
             ]
    end

    test "a row needs an id, a known kind and known measures" do
      row = %{
        "kind" => "jump",
        "name" => "X",
        "dose" => "",
        "load" => "",
        "extra" => ["speed"],
        "x" => %{"power" => "1"}
      }

      assert codes(section("for_time", %{}, [[row]])) == [
               {"blocks.0.0.id", "required"},
               {"blocks.0.0.kind", "invalid"},
               {"blocks.0.0.extra.0", "unknown_measure"},
               {"blocks.0.0.x.power", "unknown_measure"}
             ]

      cell_row = ex("a", "Row", "", "", %{"cells" => [%{"d" => "10", "watts" => "200"}, "x"]})

      assert codes(section("sets", %{}, [[cell_row]])) == [
               {"blocks.0.0.cells.0.watts", "unknown_measure"},
               {"blocks.0.0.cells.1", "invalid"}
             ]
    end

    test "doses that do not read" do
      assert codes(section("for_time", %{}, [[ex("a", "Run", "lots")]])) == [
               {"blocks.0.0.dose", "bad_dose"}
             ]

      row = ex("a", "Run", "", "", %{"cells" => [%{"d" => "0"}, %{"d" => "4×8-6"}]})

      assert codes(section("sets", %{}, [[row]])) == [
               {"blocks.0.0.cells.0.d", "bad_dose"},
               {"blocks.0.0.cells.1.d", "bad_dose"}
             ]
    end

    test "tempo in four marks, numeric measures, RPE at most 10" do
      row =
        ex("a", "Squat", "", "", %{
          "x" => %{"tempo" => "31X", "rir" => "two"},
          "cells" => [
            %{"d" => "5", "l" => "80%", "tempo" => "3-1-x-1", "rpe" => "11"},
            %{"rpe" => "8→12", "tempo" => "fast"}
          ]
        })

      assert codes(section("sets", %{}, [[row]])) == [
               {"blocks.0.0.x.rir", "bad_number"},
               {"blocks.0.0.x.tempo", "bad_tempo"},
               {"blocks.0.0.cells.0.rpe", "rpe_max"},
               {"blocks.0.0.cells.1.rpe", "rpe_max"},
               {"blocks.0.0.cells.1.tempo", "bad_tempo"}
             ]
    end

    test "the load unit is written once per row" do
      missing =
        ex("a", "Squat", "", "", %{"cells" => cells([{"5", "60"}, {"5", "+5"}, {"5", "βαρύ"}])})

      assert codes(section("sets", %{}, [[missing]])) == [
               {"blocks.0.0.cells.0.l", "missing_unit"},
               {"blocks.0.0.cells.1.l", "missing_unit"}
             ]

      mixed =
        ex("a", "Squat", "", "", %{
          "cells" => cells([{"5", "60kg"}, {"5", "70%"}, {"5", "50→60%"}, {"5", "70"}])
        })

      assert codes(section("sets", %{}, [[mixed]])) == [
               {"blocks.0.0.cells.1.l", "mixed_units"},
               {"blocks.0.0.cells.2.l", "mixed_units"}
             ]

      assert codes(section("for_time", %{}, [[ex("a", "Clean", "5", "60")]])) == [
               {"blocks.0.0.load", "missing_unit"}
             ]
    end

    test "bounds: blocks, rows, cells, strings and notes" do
      many_blocks = for i <- 1..13, do: [ex("b#{i}", "Run", "1")]
      assert codes(section("for_time", %{}, many_blocks)) == [{"blocks", "too_many_blocks"}]

      many_rows = for i <- 1..61, do: ex("r#{i}", "Run", "1")
      assert codes(section("for_time", %{}, [many_rows])) == [{"blocks.0", "too_many_rows"}]

      assert codes(section("for_time", %{}, [[]], %{"interrupt" => many_rows})) == [
               {"interrupt", "too_many_rows"}
             ]

      many_cells = ex("a", "Run", "", "", %{"cells" => List.duplicate(%{"d" => "1"}, 31)})

      assert codes(section("sets", %{}, [[many_cells]])) == [
               {"blocks.0.0.cells", "too_many_cells"}
             ]

      long = String.duplicate("α", 201)
      note = String.duplicate("n", 2001)

      plan =
        section(
          "for_time",
          %{},
          [
            [
              ex("a", long, "1", "", %{
                "note" => note,
                "exerciseRef" => String.duplicate("e", 121)
              })
            ]
          ],
          %{
            "note" => note,
            "score" => long,
            "levelNotes" => %{"rx" => note}
          }
        )

      assert codes(plan) == [
               {"blocks.0.0.name", "too_long"},
               {"blocks.0.0.exerciseRef", "too_long"},
               {"blocks.0.0.note", "too_long"},
               {"score", "too_long"},
               {"note", "too_long"},
               {"levelNotes.rx", "too_long"}
             ]

      assert codes(Map.delete(section("rest", %{}, []), "score")) == [{"score", "required"}]
      assert codes(section("rest", %{}, "none")) == [{"blocks", "invalid"}]
      assert codes(section("rest", %{}, ["none"])) == [{"blocks.0", "invalid"}]
    end
  end

  describe "notation" do
    test "times" do
      assert Notation.parse_clock("2:00", :smart) == 120
      assert Notation.parse_clock("90″", :smart) == 90
      assert Notation.parse_clock("90", :smart) == 90
      assert Notation.parse_clock("3", :smart) == 180
      assert Notation.parse_clock("20", :min) == 1200
      assert Notation.parse_clock("3'", :min) == 180
      assert Notation.parse_clock("", :min) == nil
      assert Notation.parse_clock("soon", :min) == :bad
      assert Notation.parse_times("3-3-3-4") == %{range: false, secs: [180, 180, 180, 240]}
      assert Notation.parse_times("90-120″") == %{range: true, secs: [90, 120]}
      assert Notation.parse_times("3-0") == :bad
    end

    test "doses" do
      assert %{entries: [%{min: 12, max: 12}], unit: :reps} = Notation.parse_dose("12")
      assert %{sets: %{min: 4, max: 4}, entries: [%{min: 10}]} = Notation.parse_dose("4×10")
      assert %{entries: [_, _, _, _]} = Notation.parse_dose("12-10-8-8")
      assert %{entries: [%{min: 8, max: 12}]} = Notation.parse_dose("8-12")
      assert %{entries: [_, _, _], cont: true} = Notation.parse_dose("5-10-15…")
      assert %{entries: [%{min: 400}], unit: :m} = Notation.parse_dose("400 m")
      assert %{entries: [%{min: 1000}], unit: :m} = Notation.parse_dose("1 km")
      assert %{entries: [%{min: 15}], unit: :kcal} = Notation.parse_dose("15 cal")
      assert %{entries: [%{min: 120}], unit: :secs} = Notation.parse_dose("2:00")
      assert %{max: %{within: 60}, unit: :kcal} = Notation.parse_dose("60s max cal")
      assert %{per_side: true} = Notation.parse_dose("10/πλευρά")
      assert Notation.parse_dose("") == nil
      assert Notation.parse_dose("lots") == :bad
    end

    test "first load of a row" do
      assert Notation.first_load("60", "kg") == %{value: 60, mode: :absolute}
      assert Notation.first_load("70%", nil) == %{value: 70, mode: :pct_1rm}
      assert Notation.first_load("22.5kg", nil) == %{value: 22.5, mode: :absolute}
      assert Notation.first_load("BW", nil) == %{value: nil, mode: :bw}
      assert Notation.first_load("βαρύ", "kg") == nil
      assert Notation.first_load("+5", "kg") == nil
    end
  end
end
