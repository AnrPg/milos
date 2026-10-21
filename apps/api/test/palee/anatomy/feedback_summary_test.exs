defmodule Palee.Anatomy.FeedbackSummaryTest do
  @moduledoc "ADR-163 coach totals (pure)."
  use ExUnit.Case, async: true

  alias Palee.Anatomy.Domain.FeedbackSummary

  @goals [
    %{id: "quadriceps", role: "primary"},
    %{id: "gluteus-maximus", role: :secondary},
    %{id: "rectus-abdominis", role: "stabilizer"}
  ]

  defp row(muscles, qualities \\ []), do: %{felt_muscles: muscles, felt_qualities: qualities}

  test "hides everything but the count below three entries" do
    assert FeedbackSummary.min_entries() == 3

    assert %{entries: 2, shown: false, felt_muscles: [], felt_qualities: [], goals_not_felt: []} =
             FeedbackSummary.summarize([row(["quadriceps"]), row(["quadriceps"])], @goals)
  end

  test "rolls heads up to groups, ranks by count then taxonomy order" do
    summary =
      FeedbackSummary.summarize(
        [
          row(["vastus-medialis", "rectus-femoris", "biceps-femoris-long"], ["power", "stamina"]),
          row(["hamstrings"], ["stamina"]),
          row(["quadriceps", "unknown-muscle"], [])
        ],
        @goals
      )

    assert summary.shown and summary.entries == 3
    # Taxonomy order breaks the tie: quadriceps before hamstrings.
    assert summary.felt_muscles == [%{id: "quadriceps", count: 2}, %{id: "hamstrings", count: 2}]
    assert summary.felt_qualities == [%{id: "stamina", count: 2}, %{id: "power", count: 1}]
    # A head goal rolls up too; stabilizers are not expected to be felt.
    assert summary.goals_not_felt == ["glutes"]
  end

  test "no goals, nothing not felt" do
    assert %{goals_not_felt: []} = FeedbackSummary.summarize([row([]), row([]), row([])], [])
  end
end
