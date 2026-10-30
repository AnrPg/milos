defmodule Palee.Pantheon.Domain.StrengthTrendTest do
  use ExUnit.Case, async: true

  alias Palee.Pantheon.Domain.StrengthTrend

  @today ~D[2026-10-30]
  @before ~D[2026-08-01]
  @inside ~D[2026-10-20]

  defp record(id, name, score, on, opts \\ []) do
    %{
      id: id,
      name: name,
      unit: Keyword.get(opts, :unit, "kg"),
      current_score: Decimal.new("#{score}"),
      beaten_on: on,
      supporting_metrics: Keyword.get(opts, :metrics, %{})
    }
  end

  defp history(id, score, on, metrics \\ %{}),
    do: %{
      pr_record_id: id,
      score: Decimal.new("#{score}"),
      beaten_on: on,
      supporting_metrics: metrics
    }

  test "the mean relative gain of lifts beaten inside the window (ADR-285)" do
    records = [
      record("squat", "Back squat", 110, @inside),
      record("press", "Strict press", 55, @inside)
    ]

    history = [history("squat", 100, @before), history("press", 50, @before)]

    assert %{percent: 10.0, compared_lifts: 2, new_lifts: 0, window_days: 56, lifts: lifts} =
             StrengthTrend.calculate(records, history, @today)

    assert [
             %{name: "Back squat", from_kg: 100.0, to_kg: 110.0, gain_kg: 10.0},
             %{name: "Strict press", gain_kg: 5.0}
           ] = lifts
  end

  test "sets of several reps compare by estimated one-rep max (Epley)" do
    records = [record("dl", "Deadlift", 150, @inside, metrics: %{"reps" => 1})]
    # 5 × 120 kg ≈ 140 kg 1RM.
    history = [history("dl", 120, @before, %{"reps" => 5})]

    assert %{lifts: [%{from_kg: 140.0, to_kg: 150.0}]} =
             StrengthTrend.calculate(records, history, @today)
  end

  test "a lift first logged inside the window is new, not compared" do
    records = [record("squat", "Back squat", 110, @inside), record("clean", "Clean", 80, @inside)]
    history = [history("squat", 100, @before)]

    assert %{compared_lifts: 1, new_lifts: 1} = StrengthTrend.calculate(records, history, @today)
  end

  test "nothing to compare is nil: no kg PRs, nothing new, or only new lifts" do
    assert StrengthTrend.calculate([], [], @today) == nil

    assert StrengthTrend.calculate(
             [record("fran", "Fran", 300, @inside, unit: "mins_secs")],
             [],
             @today
           ) ==
             nil

    assert StrengthTrend.calculate([record("squat", "Back squat", 100, @before)], [], @today) ==
             nil

    assert StrengthTrend.calculate([record("squat", "Back squat", 100, @inside)], [], @today) ==
             nil
  end

  test "a score edited down never shows as a loss" do
    records = [record("squat", "Back squat", 90, @inside)]
    history = [history("squat", 100, @before)]

    assert %{percent: +0.0, lifts: [%{gain_kg: +0.0}]} =
             StrengthTrend.calculate(records, history, @today)
  end

  test "reads the ISO dates and plain numbers the store hands over" do
    records = [
      %{
        id: "squat",
        name: "Back squat",
        unit: "kg",
        current_score: 110.0,
        beaten_on: "2026-10-20",
        supporting_metrics: %{}
      }
    ]

    history = [
      %{pr_record_id: "squat", score: 100.0, beaten_on: "2026-08-01", supporting_metrics: %{}}
    ]

    assert %{percent: 10.0} = StrengthTrend.calculate(records, history, @today)
  end

  test "estimated_one_rep_max/2 matches the web's rule" do
    assert StrengthTrend.estimated_one_rep_max(100, 1) == 100.0
    assert StrengthTrend.estimated_one_rep_max(100, 5) == 116.5
    assert StrengthTrend.estimated_one_rep_max(100, 13) == nil
    assert StrengthTrend.estimated_one_rep_max(0, 1) == nil
  end
end
