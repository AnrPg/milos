defmodule MilosTraining.Anatomy.CoverageTest do
  @moduledoc "ADR-164: coverage weighting, reach, levels, aggregation and node exercises. Pure."
  use ExUnit.Case, async: true

  alias MilosTraining.Anatomy.Domain.{Coverage, CoverageWeighting, NodeExercises}

  describe "CoverageWeighting" do
    test "primary counts a set, secondary half, stabilizer nothing" do
      assert CoverageWeighting.weight(:primary) == 1.0
      assert CoverageWeighting.weight("secondary") == 0.5
      assert CoverageWeighting.weight(:stabilizer) == 0.0
      assert CoverageWeighting.weight("bogus") == 0.0
    end

    test "a head reaches its group and region; a group its heads and region" do
      assert Enum.sort(CoverageWeighting.reached_nodes("rectus-femoris")) ==
               Enum.sort(["rectus-femoris", "quadriceps", "thighs"])

      reached = CoverageWeighting.reached_nodes("hamstrings")
      assert "hamstrings" in reached and "thighs" in reached
      assert "semitendinosus" in reached and "biceps-femoris-long" in reached
      refute "quadriceps" in reached

      # A group without heads reaches itself and its region.
      assert Enum.sort(CoverageWeighting.reached_nodes("latissimus-dorsi")) ==
               ["latissimus-dorsi", "upper-back"]

      assert CoverageWeighting.reached_nodes("thighs") == []
      assert CoverageWeighting.reached_nodes("nope") == []
    end

    test "exercise weights keep the strongest weight per node and drop stabilizers" do
      weights = CoverageWeighting.exercise_weights("back-squat")
      assert weights["quadriceps"] == 1.0
      assert weights["vastus-lateralis"] == 1.0
      assert weights["thighs"] == 1.0
      assert weights["hamstrings"] == 0.5
      # The core only stabilizes a squat.
      refute Map.has_key?(weights, "rectus-abdominis")
      refute Map.has_key?(weights, "core")
      assert CoverageWeighting.exercise_weights("unknown") == %{}
      assert CoverageWeighting.exercise_weights(nil) == %{}
    end

    test "levels compare weighted sets per week with explicit thresholds" do
      assert CoverageWeighting.thresholds() == %{medium: 3.0, high: 8.0}
      assert CoverageWeighting.level(0, 4) == "none"
      assert CoverageWeighting.level(0.5, 4) == "low"
      assert CoverageWeighting.level(11.5, 4) == "low"
      assert CoverageWeighting.level(12, 4) == "medium"
      assert CoverageWeighting.level(31.5, 4) == "medium"
      assert CoverageWeighting.level(32, 4) == "high"
      assert CoverageWeighting.level(8, 1) == "high"
    end

    test "ranges" do
      assert CoverageWeighting.parse_range(nil) == {:ok, "4w", 4}
      assert CoverageWeighting.parse_range("1w") == {:ok, "1w", 1}
      assert CoverageWeighting.parse_range("12w") == {:ok, "12w", 12}
      assert CoverageWeighting.parse_range("6m") == {:error, :invalid_range}
      assert CoverageWeighting.ranges() == ["1w", "4w", "12w"]
    end
  end

  describe "Coverage.build/3" do
    test "sums weighted sets per node, once per node per exercise, in tree order" do
      performances = [
        %{exercises: [%{exercise_ref: "back-squat", sets: 5}]},
        %{
          exercises: [
            %{exercise_ref: "deadlift", sets: 3},
            %{exercise_ref: nil, sets: 2},
            %{exercise_ref: "not-a-catalog-id", sets: 1}
          ]
        }
      ]

      coverage = Coverage.build(performances, [], 1)
      nodes = Map.new(coverage.nodes, &{&1.id, &1})

      assert coverage.sessions == 2
      assert coverage.exercises == %{recognized: 2, unrecognized: 2}

      # Back squat: quadriceps primary (5); deadlift: quadriceps secondary (1.5).
      assert nodes["quadriceps"].sets == 6.5
      assert nodes["quadriceps"].level == "medium"
      # Hamstrings: squat secondary 2.5 + deadlift primary 3.
      assert nodes["hamstrings"].sets == 5.5
      # A group target counts for each of its heads.
      assert nodes["semitendinosus"].sets == 5.5
      # Thighs: once per exercise at the strongest weight: 5 + 3.
      assert nodes["thighs"].sets == 8.0
      assert nodes["thighs"].level == "high"
      assert nodes["thighs"].kind == "region"

      assert nodes["quadriceps"].top_exercises == [
               %{exercise_ref: "back-squat", sets: 5.0},
               %{exercise_ref: "deadlift", sets: 1.5}
             ]

      # Stabilizers add nothing; untouched nodes are not listed.
      refute Map.has_key?(nodes, "rectus-abdominis")
      refute Map.has_key?(nodes, "biceps-brachii")

      ids = Enum.map(coverage.nodes, & &1.id)
      assert Enum.find_index(ids, &(&1 == "thighs")) < Enum.find_index(ids, &(&1 == "quadriceps"))
    end

    test "per-week figures and levels follow the range length" do
      coverage = Coverage.build([%{exercises: [%{exercise_ref: "back-squat", sets: 12}]}], [], 4)
      quads = Enum.find(coverage.nodes, &(&1.id == "quadriceps"))
      assert quads.sets == 12.0 and quads.per_week == 3.0 and quads.level == "medium"
    end

    test "felt feedback counts entries per node, each entry once" do
      felt = [
        %{felt_muscles: ["rectus-femoris", "quadriceps"]},
        %{felt_muscles: ["rectus-abdominis"]},
        %{felt_muscles: []}
      ]

      nodes = Map.new(Coverage.build([], felt, 4).nodes, &{&1.id, &1})
      assert nodes["quadriceps"].felt == 1
      assert nodes["thighs"].felt == 1
      assert nodes["rectus-femoris"].felt == 1
      # A felt group reaches its heads.
      assert nodes["vastus-medialis"].felt == 1
      assert nodes["rectus-abdominis"].felt == 1
      assert nodes["quadriceps"].sets == 0.0 and nodes["quadriceps"].level == "none"
    end

    test "missing set counts are one set" do
      nodes =
        Coverage.build([%{exercises: [%{exercise_ref: "air-squat", sets: nil}]}], [], 4).nodes

      assert Enum.find(nodes, &(&1.id == "quadriceps")).sets == 1.0
    end

    test "nothing done is an empty coverage" do
      assert Coverage.build([], [], 4) == %{
               sessions: 0,
               exercises: %{recognized: 0, unrecognized: 0},
               nodes: []
             }
    end
  end

  describe "NodeExercises.for_node/1" do
    test "exercises whose primary or secondary targets reach the node, primary first" do
      {:ok, exercises} = NodeExercises.for_node("hamstrings")
      by_ref = Map.new(exercises, &{&1.exercise_ref, &1.role})

      assert by_ref["romanian-deadlift"] == :primary
      assert by_ref["back-squat"] == :secondary
      refute Map.has_key?(by_ref, "air-squat")

      roles = Enum.map(exercises, & &1.role)
      assert roles == Enum.sort_by(roles, &if(&1 == :primary, do: 0, else: 1))
    end

    test "a head is reached by its group's exercises; a region by all of its groups" do
      {:ok, head} = NodeExercises.for_node("vastus-medialis")
      assert Enum.any?(head, &(&1.exercise_ref == "back-squat" and &1.role == :primary))

      {:ok, region} = NodeExercises.for_node("thighs")
      assert Enum.any?(region, &(&1.exercise_ref == "romanian-deadlift"))
    end

    test "stabilizer-only exercises do not train a muscle" do
      {:ok, exercises} = NodeExercises.for_node("rectus-abdominis")
      refute Enum.any?(exercises, &(&1.exercise_ref == "back-squat"))
    end

    test "unknown node" do
      assert NodeExercises.for_node("nope") == :error
    end
  end
end
