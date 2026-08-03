defmodule MilosTraining.Workouts.Domain.WorkoutDsl.ManualTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.WorkoutDsl.{Manual, Templates, Vocabulary}

  test "manual, templates, and autocomplete are generated for the same versioned registry" do
    manual = Manual.export()

    assert manual.version == 1
    assert manual.vocabulary == Vocabulary.export()
    assert manual.templates == Templates.export()

    assert Map.keys(manual.templates.sections) |> Enum.sort() ==
             Vocabulary.section_formats() |> Enum.sort()

    Enum.each(Vocabulary.section_formats(), fn format ->
      assert manual.markdown =~ "`#{Vocabulary.dsl_format(format)}`"
      assert is_binary(manual.templates.sections[format])
    end)
  end
end
