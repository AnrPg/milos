defmodule MilosTraining.Test.FakeWorkoutTextAnalyzer do
  @moduledoc false
  @behaviour MilosTraining.Workouts.Ports.WorkoutTextAnalyzer

  @impl true
  def analyze(text, options) do
    case Process.get(:fake_workout_text_analyzer) do
      nil -> {:ok, default_response(text, options)}
      fun when is_function(fun, 2) -> fun.(text, options)
    end
  end

  defp default_response(_text, options) do
    %{
      "workout" => %{"title" => "Back squat day", "type" => "strength"},
      "sections" => [
        %{
          "name" => "Main",
          "format" => "untimed",
          "exercises" => [%{"name" => "Back sqaut", "sets" => 5, "reps" => 5, "load_kg" => 100}]
        }
      ],
      "issues" => [
        %{
          "path" => "sections.0.exercises.0.name",
          "severity" => "warning",
          "message" => "locale=#{options.locale}",
          "suggestion_label" => "Fix spelling",
          "suggested_value" => "Back squat",
          "find_text" => "Back sqaut",
          "replace_text" => "Back squat"
        }
      ],
      "missing_fields" => [
        %{
          "path" => "sections.0.exercises.0.rest_seconds",
          "reason" => "Pacing",
          "suggested_value" => "120"
        }
      ]
    }
  end
end
