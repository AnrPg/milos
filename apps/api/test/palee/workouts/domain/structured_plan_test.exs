defmodule Palee.Workouts.Domain.StructuredPlanTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.StructuredPlan
  alias Palee.Workouts.Domain.StructuredPlan.Notation

  import Palee.StructuredPlanFixtures

  defp codes(plan) do
    case StructuredPlan.validate(plan) do
      :ok -> []
      {:error, errors} -> Enum.map(errors, &"#{&1.path}:#{&1.code}")
    end
  end

  defp row(more \\ %{}), do: ex("x#{System.unique_integer([:positive])}", "", "", "", more)

  describe "valid plans" do
    test "every section of the reference program reads" do
      for plan <- program() do
        assert codes(plan) == [], inspect(plan["flow"])
      end
    end

    test "decimals, words, +x and a→b loads, ranges and per-side doses read" do
      lunge =
        row(%{
          "name" => "Lunge",
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
            %{"l" => "25 κιλά"}
          ]
        })

      assert codes(section("sets", %{"sets" => "5"}, [[lunge]])) == []
    end

    test "keys outside the contract are left out of the kept plan" do
      plan =
        section("for_time", %{"rounds" => "3"}, [[ex("a", "Run", "400 m", "", %{"ui" => true})]])
        |> Map.put("draftOnly", 1)

      assert {:ok, kept} = StructuredPlan.normalize(plan)
      refute Map.has_key?(kept, "draftOnly")
      refute kept |> get_in(["blocks", Access.at(0), Access.at(0)]) |> Map.has_key?("ui")
    end

    test "rows, units and structures" do
      [_one, superset, _three, cluster | _rest] = program()

      assert [%{group: "g1", rows: [_, _, _]} = unit] =
               StructuredPlan.units(hd(superset["blocks"]))

      assert StructuredPlan.struct_of(superset, unit) == %{"kind" => "superset"}
      [single] = StructuredPlan.units(hd(cluster["blocks"]))
      assert %{"kind" => "cluster", "clusters" => "3"} = StructuredPlan.struct_of(cluster, single)
      assert length(StructuredPlan.rows(Enum.at(program(), 7))) == 2
      assert StructuredPlan.exercise_count(Enum.at(program(), 2)) == 3
    end
  end

  # The same cases, codes and paths as the web `validate.test.ts`.
  describe "errors" do
    test "not a map, an unknown flow and a wrong version" do
      assert codes("plan") == [":invalid"]
      assert codes(section("sets", %{}, []) |> Map.put("flow", "yoga")) == ["flow:unknown_flow"]
      assert codes(section("sets", %{}, []) |> Map.put("v", 2)) == ["v:bad_version"]
    end

    test "params read per kind" do
      assert codes(section("sets", %{"sets" => "3-4", "rest" => "90-120″"}, [[row()]])) == []

      assert codes(section("sets", %{"sets" => "4-3", "rest" => "120-90″"}, [[row()]])) ==
               ["params.rest:bad_param", "params.sets:bad_param"]

      assert codes(section("emom", %{"every" => "soon", "times" => "x"}, [[row()]])) ==
               ["params.every:bad_param", "params.times:bad_param"]

      assert codes(section("emom", %{"every" => "1:00", "times" => ""}, [[row()]])) == []
      assert codes(section("amrap", %{"dur" => "3-0-3"}, [[row()]])) == ["params.dur:bad_param"]

      assert codes(section("for_time", %{"rounds" => "1", "work" => "20″"}, [[row()]])) ==
               ["params.work:unknown_param"]

      # an add-on switched off may leave its value behind
      assert codes(section("for_time", %{"rounds" => "1", "intEvery" => "2:00"}, [[row()]])) == []

      assert codes(
               section("for_time", %{"rounds" => "1", "intEvery" => "x"}, [[row()]], %{
                 "mods" => %{"interrupt" => true}
               })
             ) == ["params.intEvery:bad_param"]

      assert codes(section("intervals", %{"rounds" => 8}, [])) == ["params.rounds:invalid"]
      assert codes(Map.delete(section("rest", %{}, []), "params")) == ["params:invalid"]
    end

    test "add-ons and structures only where the flow allows them" do
      assert codes(
               section("emom", %{"every" => "1:00"}, [[row()]], %{
                 "mods" => %{"interrupt" => true}
               })
             ) ==
               ["mods.interrupt:mod_not_allowed"]

      r = row()

      assert codes(
               section("amrap", %{"dur" => "12"}, [[r]], %{
                 "structs" => %{
                   r["id"] => %{"kind" => "drop", "drops" => "2", "dropby" => "-20%"}
                 }
               })
             ) ==
               ["structs.#{r["id"]}:struct_not_allowed"]

      assert codes(
               section("sets", %{"sets" => "4"}, [[r]], %{
                 "structs" => %{
                   r["id"] => %{"kind" => "cluster", "clusters" => "x", "intra" => "soon"}
                 }
               })
             ) ==
               [
                 "structs.#{r["id"]}.clusters:bad_struct_param",
                 "structs.#{r["id"]}.intra:bad_struct_param"
               ]

      assert codes(
               section("sets", %{"sets" => "4"}, [[r]], %{
                 "structs" => %{r["id"] => %{"kind" => "wave"}}
               })
             ) ==
               ["structs.#{r["id"]}:unknown_struct"]
    end

    test "the load unit is written once per row: missing_unit and mixed_unit" do
      missing = row(%{"cells" => [%{"d" => "5", "l" => "60"}, %{"l" => "70"}, %{"l" => "βαρύ"}]})

      assert codes(section("sets", %{"sets" => "2"}, [[missing]])) ==
               ["blocks.0.0.cells.0.l:missing_unit", "blocks.0.0.cells.1.l:missing_unit"]

      mixed = row(%{"cells" => [%{"l" => "60kg"}, %{"l" => "70%"}, %{"l" => "70"}]})

      assert codes(section("sets", %{"sets" => "2"}, [[mixed]])) == [
               "blocks.0.0.cells.1.l:mixed_unit"
             ]

      assert codes(section("for_time", %{"rounds" => "1"}, [[row(%{"load" => "60"})]])) ==
               ["blocks.0.0.load:missing_unit"]

      assert codes(section("for_time", %{"rounds" => "1"}, [[row(%{"load" => "βαρύ"})]])) == []
    end

    test "doses that do not read, in cells and plain values" do
      assert codes(section("sets", %{"sets" => "2"}, [[row(%{"cells" => [%{"d" => "lots"}]})]])) ==
               ["blocks.0.0.cells.0.d:bad_dose"]

      assert codes(section("amrap", %{"dur" => "7"}, [[row(%{"dose" => "lots"})]])) ==
               ["blocks.0.0.dose:bad_dose"]

      # values a flow does not read (same-every-time cells) are only bounded
      assert codes(section("amrap", %{"dur" => "7"}, [[row(%{"cells" => [%{"d" => "lots"}]})]])) ==
               []
    end

    test "measures: known, once, tempo 4 marks, RPE at most 10, numbers" do
      bad =
        row(%{
          "extra" => ["tempo", "rpe", "dist"],
          "cells" => [%{"tempo" => "31X", "rpe" => "11", "dist" => "far"}, %{"rpe" => "+1"}]
        })

      assert codes(section("sets", %{"sets" => "2"}, [[bad]])) == [
               "blocks.0.0.cells.0.tempo:bad_tempo",
               "blocks.0.0.cells.0.rpe:rpe_over_max",
               "blocks.0.0.cells.0.dist:bad_measure_value"
             ]

      assert codes(
               section("sets", %{"sets" => "2"}, [
                 [row(%{"extra" => ["rpe"], "cells" => [%{"rpe" => "7→11"}]})]
               ])
             ) ==
               ["blocks.0.0.cells.0.rpe:rpe_over_max"]

      assert codes(
               section("sets", %{"sets" => "2"}, [[row(%{"extra" => ["speed", "side", "side"]})]])
             ) ==
               ["blocks.0.0.extra.0:unknown_measure", "blocks.0.0.extra.2:duplicate_measure"]

      assert codes(
               section("amrap", %{"dur" => "7"}, [
                 [row(%{"extra" => ["rpe"], "x" => %{"rpe" => "+1"}})]
               ])
             ) ==
               ["blocks.0.0.x.rpe:bad_measure_value"]

      assert StructuredPlan.measure_issue("rpe", "10", false) == nil
      assert StructuredPlan.measure_issue("hold", "0:30", false) == nil
    end

    test "the score belongs to the flow (and its preset)" do
      assert codes(section("sets", %{}, [], %{"score" => "time"})) == ["score:unknown_score"]

      assert codes(section("emom", %{}, [], %{"preset" => "death_by", "score" => "rounds_reps"})) ==
               []
    end

    test "bounds, unique ids, rest sections and row kinds" do
      blocks = for _i <- 1..13, do: [row()]
      assert codes(section("for_time", %{"rounds" => "13"}, blocks)) == ["blocks:too_many_blocks"]

      rows = for _i <- 1..61, do: row()
      assert codes(section("for_time", %{"rounds" => "1"}, [rows])) == ["blocks.0:too_many_rows"]

      assert codes(section("for_time", %{}, [[]], %{"interrupt" => rows})) == [
               "interrupt:too_many_rows"
             ]

      many = row(%{"cells" => List.duplicate(%{"d" => "1"}, 31)})

      assert codes(section("sets", %{"sets" => "4"}, [[many]])) == [
               "blocks.0.0.cells:too_many_cells"
             ]

      long = String.duplicate("x", 201)
      note = String.duplicate("n", 2001)

      assert codes(
               section("for_time", %{"rounds" => "1"}, [[row(%{"name" => long, "note" => note})]])
             ) ==
               ["blocks.0.0.name:too_long", "blocks.0.0.note:note_too_long"]

      assert codes(
               section("for_time", %{}, [], %{"note" => note, "levelNotes" => %{"rx" => note}})
             ) ==
               ["note:note_too_long", "levelNotes.rx:note_too_long"]

      r = row()

      assert codes(section("for_time", %{"rounds" => "1"}, [[r, r]])) == [
               "blocks.0.1.id:duplicate_id"
             ]

      assert codes(section("rest", %{"dur" => "2:00"}, [[row()]])) == [
               "blocks:blocks_not_allowed"
             ]

      assert codes(section("for_time", %{}, [[row(%{"kind" => "jump"})]])) == [
               "blocks.0.0.kind:bad_row_kind"
             ]

      assert codes(section("for_time", %{}, [[Map.delete(row(), "id")]])) == [
               "blocks.0.0.id:invalid"
             ]

      assert codes(section("rest", %{}, "none")) == ["blocks:invalid"]
      assert codes(section("for_time", %{}, ["none"])) == ["blocks.0:invalid"]
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
