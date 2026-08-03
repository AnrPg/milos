defmodule MilosTraining.Workouts.Domain.WorkoutDsl.Templates do
  @moduledoc """
  Canonical coach-facing snippets generated from the DSL vocabulary.
  """

  alias MilosTraining.Workouts.Domain.WorkoutDsl.Vocabulary

  def export do
    %{
      workout: workout(),
      sections: Map.new(Vocabulary.section_formats(), &{&1, section(&1)})
    }
  end

  def workout do
    """
    [workout]
    dsl-version: 1
    title: New workout
    type: strength
    difficulty: all-levels
    estimated-duration: 60m

    #{String.trim(section("untimed"))}
    [/workout]
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  def section(format) do
    spec = Vocabulary.format_spec(format)

    [
      "[section: #{Vocabulary.dsl_format(format)}]",
      "title: #{humanize(format)}",
      Enum.map(spec.dsl_required, &required_line/1),
      if(format == "rest", do: "duration: 1m"),
      score_line(spec.scores),
      exercise_lines(format),
      "[/section]"
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp required_line(:duration_seconds), do: "duration: 12m"
  defp required_line(:interval_seconds), do: "interval: 1m"
  defp required_line(:work_seconds), do: "work: 20s"
  defp required_line(:rest_seconds), do: "rest: 10s"
  defp required_line(:rounds), do: "rounds: 8"
  defp required_line(:cycles), do: "cycles: 6"
  defp required_line(:intra_rest_seconds), do: "intra-set-rest: 20s"
  defp required_line(:sets), do: "sets: 4"
  defp required_line(:effort_seconds), do: "effort-duration: 3m"
  defp required_line(:start_reps), do: "start-reps: 2"
  defp required_line(:step_reps), do: "step-reps: 2"
  defp required_line(:min_reps), do: "minimum-reps: 2"
  defp required_line(:peak_reps), do: "peak-reps: 10"
  defp required_line(:kcal_target), do: "calorie-target: 50"
  defp required_line(field), do: "#{Vocabulary.dsl_key_for_timer_field(field)}: value"

  defp score_line([]), do: nil
  defp score_line([score | _rest]), do: "score: #{score}"

  defp exercise_lines("rest"), do: nil

  defp exercise_lines(_format) do
    [
      "[exercise: Air Squat]",
      "sets: 3",
      "reps: 10",
      "!coach-note:",
      "Add coaching intent here.",
      "[/exercise]"
    ]
  end

  defp humanize(format) do
    format
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
