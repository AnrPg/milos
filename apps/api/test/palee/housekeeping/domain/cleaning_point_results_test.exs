defmodule Palee.Housekeeping.Domain.CleaningPointResultsTest do
  use ExUnit.Case, async: true

  alias Palee.Housekeeping.Domain.CleaningPolicy

  @points [
    %{id: "p1", instruction: "Drains", media_id: "m1"},
    %{id: "p2", instruction: "Mirrors", media_id: "m2"}
  ]

  test "every point answered once, in the points' order, with a snapshot of the point" do
    assert {:ok, [first, second]} =
             CleaningPolicy.point_results(@points, [
               %{"point_id" => "p2", "status" => "not_cleaned", "note" => " No spray "},
               %{point_id: "p1", status: :cleaned, after_media_id: "a1"}
             ])

    assert first == %{
             "point_id" => "p1",
             "instruction" => "Drains",
             "media_id" => "m1",
             "status" => "cleaned",
             "note" => nil,
             "after_media_id" => "a1"
           }

    assert %{"status" => "not_cleaned", "note" => "No spray"} = second
    assert [%{"point_id" => "p2"}] = CleaningPolicy.not_cleaned([first, second])
  end

  test "a room without points takes no answers" do
    assert CleaningPolicy.point_results([], nil) == {:ok, []}
  end

  test "missing, repeated, unknown or malformed answers are refused" do
    cleaned = &%{point_id: &1, status: "cleaned"}

    assert CleaningPolicy.point_results(@points, [cleaned.("p1")]) ==
             {:error, :cleaning_point_unanswered}

    assert CleaningPolicy.point_results(@points, [cleaned.("p1"), cleaned.("p1")]) ==
             {:error, :invalid_point_results}

    assert CleaningPolicy.point_results(@points, [cleaned.("p1"), cleaned.("p2"), cleaned.("x")]) ==
             {:error, :invalid_point_results}

    assert CleaningPolicy.point_results(@points, [
             cleaned.("p1"),
             %{point_id: "p2", status: "dirty"}
           ]) == {:error, :invalid_point_results}

    assert CleaningPolicy.point_results(@points, :nope) == {:error, :invalid_point_results}
  end

  test "a point not cleaned needs a note" do
    assert CleaningPolicy.point_results(@points, [
             %{point_id: "p1", status: "cleaned"},
             %{point_id: "p2", status: "not_cleaned", note: "  "}
           ]) == {:error, :cleaning_point_note_required}
  end
end
