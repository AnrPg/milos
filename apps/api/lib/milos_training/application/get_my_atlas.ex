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

  alias MilosTraining.Anatomy
  alias MilosTraining.Application.AthleteTrainingVolume

  def call(context, params, today \\ Date.utc_today()) do
    with {:ok, range, weeks} <- Anatomy.parse_coverage_range(params["range"]) do
      from = Date.add(today, -(7 * weeks - 1))
      volume = AthleteTrainingVolume.load(context, DateTime.new!(from, ~T[00:00:00], "Etc/UTC"))
      coverage = Anatomy.coverage(volume.performances, volume.felt, weeks)

      {:ok,
       Map.merge(coverage, %{
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
end
