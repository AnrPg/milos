defmodule MilosTraining.Application.ParseWorkoutDslTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Application.ParseWorkoutDsl

  test "returns canonical workout, formatted source and autocomplete vocabulary" do
    source = """
    [workout]
    dsl-version: 1
    title: Pull Strength
    type: strength
    [section: untimed]
    title: Main
    [exercise: Pull-up]
    sets: 5
    reps: 3
    [/exercise]
    [/section]
    [/workout]
    """

    assert {:ok, preview} = ParseWorkoutDsl.call(source)
    assert preview.workout.title == "Pull Strength"
    assert preview.formatted_source =~ "[exercise: Pull-up]"
    assert "untimed" in preview.vocabulary.section_formats
    assert "reps" in preview.vocabulary.exercise_parameters
  end

  test "preserves structured diagnostics for the interface layer" do
    assert {:error, diagnostics} = ParseWorkoutDsl.call("[workout]\n[/workout]")
    assert Enum.any?(diagnostics, &(&1.code == :missing_dsl_version))
  end
end
