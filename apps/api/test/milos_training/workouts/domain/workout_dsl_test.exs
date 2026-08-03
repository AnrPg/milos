defmodule MilosTraining.Workouts.Domain.WorkoutDslTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.TimerConfig
  alias MilosTraining.Workouts.Domain.WorkoutDsl
  alias MilosTraining.Workouts.Domain.WorkoutDsl.Vocabulary

  describe "canonical vocabulary" do
    test "owns the same nineteen section formats used by timer validation" do
      assert Vocabulary.section_formats() == [
               "untimed",
               "for_time",
               "train_to_exhaustion",
               "kcal_target",
               "emom",
               "complex_emom",
               "even_odd",
               "billat",
               "amrap",
               "edt",
               "death_by",
               "tabata",
               "custom_hiit",
               "cluster",
               "hrr",
               "ladder_ascending",
               "ladder_descending",
               "pyramid",
               "rest"
             ]

      Enum.each(Vocabulary.section_formats(), fn format ->
        required =
          format
          |> Vocabulary.required_timer_fields()
          |> Map.new(&{&1, 1})

        assert {:ok, %{type: ^format}} =
                 TimerConfig.normalize(Map.put(required, :type, format))
      end)
    end

    test "returns context-aware canonical completions" do
      assert "duration" in Vocabulary.suggestions(:section, "emom")
      assert "interval" in Vocabulary.suggestions(:section, "emom")
      refute "work" in Vocabulary.suggestions(:section, "emom")

      assert "reps" in Vocabulary.suggestions(:exercise)
      assert "rest-between-sets" in Vocabulary.suggestions(:exercise)
      assert "!coach-note" in Vocabulary.suggestions(:note)
    end
  end

  describe "parse/1" do
    test "compiles a canonical workout with notes, a header and explicit deload sets" do
      source = """
      [workout]
      dsl-version: 1
      title: Lower Body Strength
      type: strength

      !note:
      Keep every repetition technically consistent.

      [section: emom]
      title: Main Work
      duration: 12 min
      interval: 1 min
      score: reps

      [header]
      title: Quality first
      subtitle: Stop before technique deteriorates
      [/header]

      [exercise: Back Squat]
      progression: explicit
      sets:
      - 5 reps @ 60 %1rm
      - 5 reps @ 70 %1rm
      - 3 reps @ 80 %1rm
      - 5 reps @ 65 %1rm [deload]
      tempo: 31X1
      rest-between-sets: 2 min 30 sec

      !coach-note:
      Reduce the final heavy set if bar speed drops.
      [/exercise]
      [/section]
      [/workout]
      """

      assert {:ok, result} = WorkoutDsl.parse(source)
      assert result.version == 1
      assert result.diagnostics == []

      assert %{
               title: "Lower Body Strength",
               type: "strength",
               note: "Keep every repetition technically consistent.",
               sections: [section]
             } = result.workout

      assert section.name == "Main Work"
      assert section.timer_config.type == "emom"
      assert section.timer_config.duration_seconds == 720
      assert section.timer_config.interval_seconds == 60
      assert section.scoreable
      assert section.score_config.type == "reps"

      assert [header, exercise] = section.exercises
      assert header.item_type == "header"
      assert header.name == "Quality first"
      assert header.subtitle == "Stop before technique deteriorates"

      assert exercise.item_type == "exercise"
      assert exercise.name == "Back Squat"
      assert exercise.sets == 4
      assert exercise.tempo == "31X1"
      assert exercise.rest_seconds == 150
      refute Map.has_key?(exercise, :note)

      assert [%{type: "coach-note", body: "Reduce the final heavy set if bar speed drops."}] =
               exercise.notes

      assert Enum.map(exercise.set_prescriptions, & &1.load_value) == [60, 70, 80, 65]
      assert Enum.map(exercise.set_prescriptions, & &1.prescription_value) == [5, 5, 3, 5]
      assert Enum.all?(exercise.set_prescriptions, &(&1.load_mode == "pct_1rm"))
      assert List.last(exercise.set_prescriptions).note == "deload"
      assert exercise.load_progression.mode == "per_set"
      assert exercise.load_progression.direction == "increase"
    end

    test "returns positioned diagnostics instead of guessing invalid input" do
      source = """
      [workout]
      dsl-version: 1
      title: Invalid EMOM
      type: strength
      [section: emom]
      title: Main
      duration: twelve minutes
      [exercise: Squat]
      distance: 500 m
      [/exercise]
      [/section]
      [/workout]
      """

      assert {:error, diagnostics} = WorkoutDsl.parse(source)

      assert Enum.any?(diagnostics, fn diagnostic ->
               diagnostic.code == :invalid_duration and diagnostic.line == 7
             end)

      refute Enum.any?(diagnostics, fn diagnostic ->
               diagnostic.code in [
                 :unresolved_exercise_reference,
                 :ambiguous_exercise_reference,
                 :exercise_alias_resolved
               ]
             end)

      assert Enum.any?(diagnostics, fn diagnostic ->
               diagnostic.code == :missing_required_timer_field and
                 diagnostic.params.field == "duration"
             end)
    end

    test "rejects unclosed and mismatched blocks with source positions" do
      source = """
      [workout]
      dsl-version: 1
      title: Broken
      type: strength
      [section: untimed]
      title: Main
      [exercise: Push-up]
      reps: 10
      [/section]
      """

      assert {:error, diagnostics} = WorkoutDsl.parse(source)
      assert Enum.any?(diagnostics, &(&1.code == :mismatched_closing_block and &1.line == 9))
      assert Enum.any?(diagnostics, &(&1.code == :unclosed_block))
    end

    test "preserves free-text exercise labels and accepts singular set without diagnostics" do
      source = """
      [workout]
      dsl-version: 1
      title: Coach vocabulary
      type: strength
      [section: untimed]
      title: Main
      [exercise: Squat Snatch]
      set: 3
      reps: 5
      [/exercise]
      [exercise: My Odd Carry]
      distance: 500m
      [/exercise]
      [/section]
      [/workout]
      """

      assert {:ok, result} = WorkoutDsl.parse(source)
      assert result.diagnostics == []
      assert [alias_label, custom_label] = hd(result.workout.sections).exercises
      assert alias_label.name == "Squat Snatch"
      assert alias_label.sets == 3
      assert custom_label.name == "My Odd Carry"
      assert WorkoutDsl.format(result.workout) =~ "sets: 3"
    end
  end

  describe "canonical formatting" do
    test "formatted source round-trips to the same canonical workout" do
      source = """
      [workout]
      dsl-version: 1
      title: Simple Strength
      type: strength
      [section: untimed]
      title: Strength
      [exercise: Deadlift]
      sets: 3
      reps: 5
      load: 100 kg
      rest-between-sets: 2 min
      [/exercise]
      [/section]
      [/workout]
      """

      assert {:ok, first} = WorkoutDsl.parse(source)
      formatted = WorkoutDsl.format(first.workout, version: first.version)
      assert {:ok, second} = WorkoutDsl.parse(formatted)
      assert second.workout == first.workout
      assert WorkoutDsl.format(second.workout, version: second.version) == formatted
    end

    test "every canonical section template parses and round-trips idempotently" do
      alias MilosTraining.Workouts.Domain.WorkoutDsl.Templates

      Enum.each(Vocabulary.section_formats(), fn format ->
        source = """
        [workout]
        dsl-version: 1
        title: #{format} conformance
        type: strength
        #{Templates.section(format)}
        [/workout]
        """

        assert {:ok, first} = WorkoutDsl.parse(source), "template failed for #{format}"
        formatted = WorkoutDsl.format(first.workout, version: first.version)
        assert {:ok, second} = WorkoutDsl.parse(formatted), "round-trip failed for #{format}"
        assert second.workout == first.workout
        assert WorkoutDsl.format(second.workout, version: second.version) == formatted
      end)
    end

    test "nested sections, groups, scales, rich metadata and linear deload survive round-trip" do
      source = """
      [workout]
      dsl-version: 1
      canonical-schema-version: 1
      source-revision: 7
      title: Complete Strength Day
      subtitle: Lower body emphasis
      description: Build strength without losing movement quality.
      type: strength
      difficulty: intermediate
      estimated-duration: 75m
      equipment: barbell, rack, pull-up bar
      tags: strength, deload
      target-population: Intermediate athletes
      objective: Strength with controlled fatigue
      location: Main gym
      modality: Mixed
      program-position: Week 3 Day 2
      default-scale: rx
      is-team-workout: false
      !athlete-note:
      Move with intent and stop if technique deteriorates.

      [section: straight-sets]
      title: Strength
      subtitle: Primary work
      rest-between-exercises: 2m
      rest-before-next-section: 3m
      [header]
      title: Main lifts
      subtitle: Quality before load
      [/header]
      [exercise: Back Squat]
      subtitle: Controlled eccentric
      progression: linear
      sets: 4
      reps: 5
      load-start: 80%1rm
      load-step: -5%1rm
      tempo: 31X1
      target-rpe: 8
      target-rir: 2
      percentage-of: training max
      side: both
      stance: shoulder width
      grip: full
      range-of-motion: below parallel
      equipment: barbell, rack
      rest-between-reps: 2s
      rest-between-sets: 2m
      rest-after-exercise: 90s
      rest-until: breathing controlled
      rest-range: 90s..2m
      [scale: beginner]
      variation: Goblet Squat
      sets: 4
      reps: 8
      load: 16kg
      !scaling-note:
      Preserve full depth.
      [/scale]
      [/exercise]
      [section: amrap]
      title: Assistance
      duration: 8m
      score: rounds+reps
      [group: superset]
      title: Pull and press
      sets: 3
      rest-between-groups: 60s
      [exercise: Pull-up]
      reps: 8
      load: bw
      [/exercise]
      [exercise: Push-up]
      reps: 12
      load: bw
      [/exercise]
      [/group]
      [/section]
      [/section]
      [/workout]
      """

      assert {:ok, first} = WorkoutDsl.parse(source)
      formatted = WorkoutDsl.format(first.workout, version: first.version)
      assert {:ok, second} = WorkoutDsl.parse(formatted)
      assert second.workout == first.workout

      [section] = first.workout.sections
      [header, squat] = section.exercises
      [assistance] = section.sections
      assert header.item_type == "header"
      assert squat.load_progression.direction == "decrease"
      assert Enum.map(squat.set_prescriptions, & &1.load_value) == [80, 75, 70, 65]
      assert [%{scale_level_slug: "beginner"}] = squat.variations
      assert length(assistance.exercises) == 2
      assert Enum.uniq(Enum.map(assistance.exercises, & &1.superset_group_id)) |> length() == 1
    end

    test "representative randomized prescriptions remain stable after canonical formatting" do
      for sets <- 1..8, reps <- [1, 3, 5, 8, 12], load <- [0, 20, 42.5, 80] do
        source = """
        [workout]
        dsl-version: 1
        title: Generated #{sets}-#{reps}-#{load}
        type: strength
        [section: untimed]
        title: Main
        [exercise: Deadlift]
        sets: #{sets}
        reps: #{reps}
        load: #{load}kg
        [/exercise]
        [/section]
        [/workout]
        """

        assert {:ok, first} = WorkoutDsl.parse(source)
        assert {:ok, second} = first.workout |> WorkoutDsl.format() |> WorkoutDsl.parse()
        assert second.workout == first.workout
      end
    end
  end

  describe "bounded and strict input" do
    test "rejects oversized source before tokenization" do
      assert {:error, [%{code: :source_too_large}]} =
               WorkoutDsl.parse(String.duplicate("x", 200_001))
    end

    test "catalog capabilities do not constrain a free-text exercise prescription" do
      source = """
      [workout]
      dsl-version: 1
      title: Invalid capability
      type: strength
      [section: untimed]
      title: Main
      [exercise: Air Squat]
      distance: 500m
      [/exercise]
      [/section]
      [/workout]
      """

      assert {:ok, result} = WorkoutDsl.parse(source)
      assert result.diagnostics == []

      assert hd(hd(result.workout.sections).exercises).prescription_metadata["distance_meters"] ==
               500
    end
  end
end
