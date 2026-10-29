defmodule Palee.Execution.Domain.PlanActualsTest do
  use ExUnit.Case, async: true

  alias Palee.Execution.Domain.PlanActuals

  @section "11111111-1111-4111-8111-111111111111"
  @rows %{@section => %{"r1" => 0, "r2" => 1, "i1" => -1}}

  defp entry(overrides \\ %{}) do
    Map.merge(
      %{
        "section_id" => @section,
        "row_id" => "r1",
        "exercise_name" => "Back Squat",
        "exercise_ref" => "back-squat",
        "block_index" => 0,
        "round_index" => 1,
        "part_index" => 0,
        "phase_index" => 0,
        "interrupt" => false,
        "prescribed_reps_text" => "5",
        "prescribed_load_text" => "70%",
        "prescribed_reps" => 5,
        "prescribed_load_kg" => 87.5,
        "prescribed_load_pct" => 70,
        "one_rep_max_kg" => 125,
        "actual_reps" => 5,
        "actual_load_kg" => 90,
        "logged" => true
      },
      overrides
    )
  end

  test "a record reads with two-decimal decimals" do
    assert {:ok, [record]} = PlanActuals.normalize([entry()], @rows)

    assert %{
             section_id: @section,
             row_id: "r1",
             block_index: 0,
             round_index: 1,
             interrupt: false,
             logged: true,
             exercise_ref: "back-squat"
           } = record

    assert Decimal.equal?(record.prescribed_load_kg, Decimal.new("87.5"))
    assert Decimal.equal?(record.prescribed_load_pct, 70)
    assert Decimal.equal?(record.one_rep_max_kg, 125)
    assert Decimal.equal?(PlanActuals.tonnage(record), 450)

    assert %{actual_load_kg: 90, prescribed_load_kg: 87.5} = PlanActuals.to_json(record)
  end

  test "nil is none; a 1RM and numbers may be null; an empty ref is nil" do
    assert {:ok, []} = PlanActuals.normalize(nil, @rows)

    assert {:ok, [record]} =
             PlanActuals.normalize(
               [
                 entry(%{
                   "one_rep_max_kg" => nil,
                   "prescribed_load_kg" => nil,
                   "actual_load_kg" => nil,
                   "exercise_ref" => ""
                 })
               ],
               @rows
             )

    assert %{one_rep_max_kg: nil, actual_load_kg: nil, exercise_ref: nil} = record
    assert Decimal.equal?(PlanActuals.tonnage(record), 0)
  end

  test "interruption records: block -1, interrupt true, round = which interruption" do
    assert {:ok, [%{interrupt: true, block_index: -1, round_index: 3}]} =
             PlanActuals.normalize(
               [
                 entry(%{
                   "row_id" => "i1",
                   "block_index" => -1,
                   "interrupt" => true,
                   "round_index" => 3
                 })
               ],
               @rows
             )

    # An interruption row claimed as a main-run set, or the other way round.
    for bad <- [
          %{"row_id" => "i1", "block_index" => -1, "interrupt" => false},
          %{"row_id" => "i1", "block_index" => 0, "interrupt" => true},
          %{"row_id" => "r1", "block_index" => -1, "interrupt" => true}
        ] do
      assert {:error, :bad_request} = PlanActuals.normalize([entry(bad)], @rows)
    end
  end

  test "records the plan could not produce are refused" do
    for bad <- [
          %{"section_id" => "22222222-2222-4222-8222-222222222222"},
          %{"row_id" => "nope"},
          %{"row_id" => ""},
          %{"block_index" => 1},
          %{"round_index" => 0},
          %{"part_index" => -1},
          %{"actual_reps" => -1},
          %{"actual_load_kg" => "90"},
          %{"interrupt" => "no"},
          %{"logged" => 1},
          %{"exercise_name" => String.duplicate("x", 201)},
          %{"prescribed_reps_text" => 5}
        ] do
      assert {:error, :bad_request} = PlanActuals.normalize([entry(bad)], @rows),
             "expected #{inspect(bad)} to be refused"
    end

    assert {:error, :bad_request} = PlanActuals.normalize("x", @rows)
    assert {:error, :bad_request} = PlanActuals.normalize(["x"], @rows)

    too_many = List.duplicate(entry(), PlanActuals.max_records() + 1)
    assert {:error, :bad_request} = PlanActuals.normalize(too_many, @rows)
  end

  test "the same place twice keeps the last record, in run order" do
    entries = [
      entry(%{"actual_reps" => 3}),
      entry(%{"row_id" => "r2", "block_index" => 1}),
      entry(%{"actual_reps" => 4})
    ]

    assert {:ok, [first, second]} = PlanActuals.normalize(entries, @rows)
    assert first.row_id == "r2"
    assert Decimal.equal?(second.actual_reps, 4)
  end

  test "atom keys read too" do
    atoms = Map.new(entry(), fn {key, value} -> {String.to_existing_atom(key), value} end)
    assert {:ok, [_record]} = PlanActuals.normalize([atoms], @rows)
  end
end
