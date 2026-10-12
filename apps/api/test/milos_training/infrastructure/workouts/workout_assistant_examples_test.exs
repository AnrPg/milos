defmodule MilosTraining.Infrastructure.Workouts.WorkoutAssistantExamplesTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Infrastructure.Workouts.{GeminiPrompts, WorkoutAssistantExamples}
  alias MilosTraining.Workouts.Domain.FreeTextAnalysis
  alias MilosTraining.Workouts.Domain.WorkoutAssistant.Contract

  test "there are examples and each is complete" do
    assert length(WorkoutAssistantExamples.all()) >= 1

    for example <- WorkoutAssistantExamples.all() do
      assert is_binary(example["description"]), example["file"]
      assert is_binary(example["text"]), example["file"]
      assert is_map(example["answer"]), example["file"]
    end
  end

  # The examples teach the model what a correct answer is, so they must be
  # correct themselves.
  test "every example answer satisfies the contract against its text" do
    for example <- WorkoutAssistantExamples.all() do
      assert Contract.check(example["answer"], example["text"]) == [],
             "#{example["file"]}: #{inspect(Contract.check(example["answer"], example["text"]))}"
    end
  end

  test "every example normalizes without blocking problems and keeps its assumptions" do
    for example <- WorkoutAssistantExamples.all() do
      result = FreeTextAnalysis.normalize(example["answer"], example["text"])
      assert result["summary"]["blocking"] == 0, example["file"]

      refute Enum.any?(
               result["issues"],
               &(&1["code"] in ~w(invalid_timer unknown_format invalid_value))
             ),
             "#{example["file"]}: #{inspect(result["issues"])}"

      assumptions =
        (example["answer"]["assumptions"] || [])
        |> Enum.map(&String.replace(&1["path"], ~r/\.timer\..+$/, ".timer"))
        |> Enum.uniq()
        |> length()

      kept = Enum.count(result["issues"], &(&1["code"] == "assumption"))
      assert kept == assumptions, "#{example["file"]}: #{kept} of #{assumptions} assumptions kept"
    end
  end

  test "examples reach both the structure and the parser prompts" do
    [first | _rest] = WorkoutAssistantExamples.all()
    assert GeminiPrompts.parser("en") =~ first["description"]
    assert GeminiPrompts.structure("en") =~ hd(first["answer"]["sections"])["name"]
  end
end
