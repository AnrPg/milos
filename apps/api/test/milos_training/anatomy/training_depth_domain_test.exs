defmodule MilosTraining.Anatomy.TrainingDepthDomainTest do
  @moduledoc """
  ADR-165, pure: the coverage summary (major groups, push:pull, quad:ham),
  the qualities profile and training load (session RPE, acute:chronic,
  sufficiency and bands).
  """
  use ExUnit.Case, async: true

  alias MilosTraining.Analytics.Domain.TrainingLoad
  alias MilosTraining.Anatomy.Domain.{Coverage, CoverageBalance, QualityProfile}

  defp perf(exercises),
    do: %{exercises: Enum.map(exercises, fn {ref, sets} -> %{exercise_ref: ref, sets: sets} end)}

  describe "CoverageBalance" do
    test "most and least trained major groups, levels per week" do
      performances = [perf([{"back-squat", 5}, {"bench-press", 3}])]
      coverage = Coverage.build(performances, [], 1)
      summary = CoverageBalance.summarize(coverage.nodes, performances)

      # Ties keep the major groups' order.
      assert Enum.map(summary.most, & &1.id) == ["glutes", "quadriceps", "pectoralis-major"]
      assert %{sets: 5.0, per_week: 5.0, level: "medium"} = Enum.at(summary.most, 1)
      assert length(summary.least) == 3
      assert Enum.all?(summary.least, &(&1.level in ["none", "low"]))
      assert hd(summary.least).sets == 0.0
      refute Enum.any?(summary.least, &(&1.id == "quadriceps"))
    end

    test "nothing trained: no most, no least, no ratios" do
      summary = CoverageBalance.summarize([], [])
      assert summary.most == [] and summary.least == []
      assert summary.balance.push_pull_ratio == nil and summary.balance.quad_ham_ratio == nil
    end

    test "push:pull and quad:ham from primary muscles, half each when both" do
      performances = [
        perf([{"bench-press", 4}, {"strict-press", 2}, {"pull-up", 3}, {"muscle-up", 2}]),
        perf([{"back-squat", 6}, {"romanian-deadlift", 2}, {"clean", 2}, {"yoga", 9}])
      ]

      balance = CoverageBalance.summarize([], performances).balance
      # Push: bench 4 + press 2 + muscle-up 1; pull: pull-up 3 + muscle-up 1.
      assert balance.push == 7.0 and balance.pull == 4.0
      assert balance.push_pull_ratio == 1.75
      # Quad: squat 6 + clean 1; ham: RDL 2 + clean 1.
      assert balance.quad == 7.0 and balance.ham == 3.0
      assert balance.quad_ham_ratio == 2.33
    end

    test "no ratio until both sides have sets and reach the minimum together" do
      assert CoverageBalance.summarize([], [perf([{"bench-press", 5}])]).balance.push_pull_ratio ==
               nil

      assert CoverageBalance.summarize([], [perf([{"bench-press", 2}, {"pull-up", 1}])]).balance.push_pull_ratio ==
               nil

      assert CoverageBalance.summarize([], [perf([{"bench-press", 2}, {"pull-up", 2}])]).balance.push_pull_ratio ==
               1.0
    end
  end

  describe "QualityProfile" do
    test "sets per quality, a 0..1 shape and felt counts, always ten axes" do
      profile =
        QualityProfile.build(
          [perf([{"back-squat", 5}]), perf([{"thruster", 3}]), perf([{"yoga", 2}])],
          [
            %{felt_qualities: ["strength", "strength"]},
            %{felt_qualities: ["stamina"]},
            %{felt_qualities: []}
          ]
        )

      by_id = Map.new(profile.qualities, &{&1.id, &1})
      assert length(profile.qualities) == 10
      assert hd(profile.qualities).id == "cardiorespiratory-endurance"
      assert profile.sessions == 2
      assert by_id["strength"] == %{id: "strength", sets: 5, score: 1.0, felt: 1}
      assert by_id["stamina"].sets == 3 and by_id["stamina"].score == 0.6
      assert by_id["stamina"].felt == 1
      assert by_id["balance"] == %{id: "balance", sets: 0, score: 0.0, felt: 0}
    end

    test "no training: every score is zero" do
      profile = QualityProfile.build([], [])
      assert profile.sessions == 0
      assert Enum.all?(profile.qualities, &(&1.score == 0.0 and &1.sets == 0))
    end
  end

  describe "TrainingLoad" do
    @today ~D[2026-10-21]

    defp session(days_ago, rpe, minutes),
      do: %{on: Date.add(@today, -days_ago), rpe: rpe, minutes: minutes}

    test "acute, chronic and the ratio with enough history" do
      sessions = [
        # This week (last 7 days): 7×60 + 8×45 = 780.
        session(0, 7, 60),
        session(3, 8, 45),
        # Earlier blocks of the 28 days: 300 each.
        session(8, 5, 60),
        session(15, 6, 50),
        session(22, 5, 60),
        # Unrated sessions count but add nothing.
        session(2, nil, 40),
        session(4, 6, nil),
        # Outside the 28 days, inside the chart.
        session(40, 5, 30)
      ]

      load = TrainingLoad.build(sessions, @today)

      assert load.acute == 780
      # (780 + 300 + 300 + 300) / 4 = 420.
      assert load.chronic == 420
      assert load.ratio == 1.86
      assert load.band == "well_above"
      assert load.sufficient
      assert load.rated_sessions == 5
      assert load.unrated_sessions == 2

      assert length(load.weeks) == 8
      assert List.last(load.weeks).week_start == ~D[2026-10-19]
      assert Enum.sum(Enum.map(load.weeks, & &1.load)) == 780 + 900 + 150
    end

    test "bands are neutral descriptions of the ratio" do
      steady = for days <- [0, 8, 15, 22], do: session(days, 5, 60)
      assert %{ratio: 1.0, band: "steady"} = TrainingLoad.build(steady, @today)

      light = [session(1, 2, 30) | for(days <- [8, 15, 22], do: session(days, 5, 60))]
      assert %{band: "below"} = TrainingLoad.build(light, @today)

      rising = [session(1, 7, 60) | for(days <- [8, 15, 22], do: session(days, 5, 60))]
      # 420 / ((420 + 900) / 4) = 1.27 is still steady; 1.4 is above.
      assert %{band: "steady"} = TrainingLoad.build(rising, @today)

      above = [
        session(1, 7, 60),
        session(2, 2, 30) | for(days <- [8, 15, 22], do: session(days, 5, 60))
      ]

      assert %{band: "above"} = TrainingLoad.build(above, @today)
    end

    test "no ratio before three of the four weeks have load" do
      load = TrainingLoad.build([session(0, 8, 60), session(10, 6, 60)], @today)
      refute load.sufficient
      assert load.ratio == nil and load.band == nil
      assert load.acute == 480

      empty = TrainingLoad.build([], @today)
      refute empty.sufficient
      assert empty.acute == 0 and empty.chronic == 0
      assert Enum.all?(empty.weeks, &(&1.load == 0))
    end

    test "window start covers both the chart and the chronic window" do
      assert TrainingLoad.window_start(@today) == ~D[2026-08-31]
    end
  end
end
