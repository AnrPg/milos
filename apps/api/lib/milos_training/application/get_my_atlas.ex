defmodule MilosTraining.Application.GetMyAtlas do
  @moduledoc """
  `GET /api/me/atlas?range=4w` (ADR-164): the member's own muscle coverage
  across every provider for the anatomy atlas. Per taxonomy node (region,
  group, head) the weighted sets in the range, sets per week, a coverage
  level, how many entries the member felt it in and the exercises that added
  the most (`Anatomy.coverage/3`, weighting in `CoverageWeighting`).

  The range ends today (UTC) and starts `7 × weeks - 1` days earlier, at
  midnight UTC. Account-level and ungated like the account Πρόοδος: it is
  the member's own data.
  """

  alias MilosTraining.Application.AthleteTrainingVolume
  alias MilosTraining.{Anatomy, Workouts}

  def call(context, params, today \\ Date.utc_today()) do
    with {:ok, range, weeks} <- Anatomy.parse_coverage_range(params["range"]) do
      from = Date.add(today, -(7 * weeks - 1))
      volume = AthleteTrainingVolume.load(context, DateTime.new!(from, ~T[00:00:00], "Etc/UTC"))
      coverage = Anatomy.coverage(volume.performances, volume.felt, weeks)

      {:ok,
       coverage
       |> Map.update!(:nodes, fn nodes -> Enum.map(nodes, &label_exercises/1) end)
       |> Map.merge(%{
         range: range,
         weeks: weeks,
         from: from,
         to: today,
         taxonomy_version: Anatomy.taxonomy_version(),
         thresholds: Anatomy.coverage_thresholds(),
         felt_entries: length(volume.felt)
       })}
    end
  end

  # The catalog label next to each top exercise, for display.
  defp label_exercises(node) do
    Map.update!(node, :top_exercises, fn exercises ->
      Enum.map(exercises, fn exercise ->
        entry = Workouts.resolve_catalog_exercise(exercise.exercise_ref, nil)
        Map.put(exercise, :label, (entry && entry.label) || exercise.exercise_ref)
      end)
    end)
  end
end
