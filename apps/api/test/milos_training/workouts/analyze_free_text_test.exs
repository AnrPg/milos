defmodule MilosTraining.Workouts.AnalyzeFreeTextTest do
  use ExUnit.Case, async: false

  alias MilosTraining.Workouts.Queries.AnalyzeFreeText

  @text "AMRAP 12\n10 pul ups"

  defp valid_answer do
    %{
      "workout" => %{"title" => "AMRAP day", "type" => "crossfit"},
      "sections" => [
        %{
          "name" => "Metcon",
          "format" => "amrap",
          "timer" => [%{"key" => "duration_seconds", "value" => "720"}],
          "exercises" => [%{"name" => "pul ups", "reps" => 10}]
        }
      ],
      "issues" => [],
      "missing_fields" => []
    }
  end

  test "asks the parser to repair contract violations and keeps the better answer" do
    parent = self()
    broken = put_in(valid_answer(), ["sections", Access.at(0), "format"], "emom")

    Process.put(:fake_workout_text_analyzer, fn _text, options ->
      send(parent, {:parse, Map.has_key?(options, :repair)})

      case options do
        %{repair: %{violations: [_ | _]}} -> {:ok, valid_answer()}
        _first -> {:ok, broken}
      end
    end)

    assert {:ok, result} = AnalyzeFreeText.call(@text, %{locale: "en"})
    assert_received {:parse, false}
    assert_received {:parse, true}
    assert result["quality"]["repair_attempts"] == 1
    assert result["quality"]["remaining_violations"] == 0
    assert hd(result["workout"]["sections"])["timer_config"]["type"] == "amrap"
  end

  test "stops repairing after two attempts and still returns the best answer" do
    broken = put_in(valid_answer(), ["sections", Access.at(0), "format"], "emom")
    Process.put(:fake_workout_text_analyzer, fn _text, _options -> {:ok, broken} end)

    assert {:ok, result} = AnalyzeFreeText.call(@text, %{locale: "en"})
    assert result["quality"]["remaining_violations"] == 1
  end

  test "merges verified proofreading corrections as actionable issues" do
    Process.put(:fake_workout_text_analyzer, fn _text, _options -> {:ok, valid_answer()} end)

    Process.put(:fake_workout_text_proofreader, fn _text, _options ->
      {:ok,
       %{
         "corrections" => [
           %{
             "find_text" => "pul ups",
             "replace_text" => "pull-ups",
             "kind" => "spelling",
             "message" => "Typo",
             "label" => "Use pull-ups"
           },
           %{"find_text" => "invented", "replace_text" => "x"}
         ]
       }}
    end)

    assert {:ok, result} = AnalyzeFreeText.call(@text, %{locale: "en"})
    assert [issue] = Enum.filter(result["issues"], &(&1["code"] == "text_correction"))
    assert issue["path"] == "sections.0.exercises.0.name"
    assert issue["suggestion"]["text_edit"] == %{"find" => "pul ups", "replace" => "pull-ups"}
    assert result["quality"]["corrections"] == 1
  end

  test "a failing or crashing proofreader never fails the analysis" do
    Process.put(:fake_workout_text_analyzer, fn _text, _options -> {:ok, valid_answer()} end)
    Process.put(:fake_workout_text_proofreader, fn _text, _options -> raise "boom" end)

    assert {:ok, result} = AnalyzeFreeText.call(@text, %{locale: "en"})
    assert result["quality"]["corrections"] == 0
  end

  test "a parser failure is returned" do
    Process.put(:fake_workout_text_analyzer, fn _text, _options ->
      {:error, :analyzer_unavailable}
    end)

    assert {:error, :analyzer_unavailable} = AnalyzeFreeText.call(@text, %{locale: "en"})
  end
end
