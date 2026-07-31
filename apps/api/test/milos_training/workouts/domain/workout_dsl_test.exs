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
      assert exercise.note == "Reduce the final heavy set if bar speed drops."

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

      assert Enum.any?(diagnostics, fn diagnostic ->
               diagnostic.code == :unknown_exercise_parameter and diagnostic.line == 9
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
  end
end
