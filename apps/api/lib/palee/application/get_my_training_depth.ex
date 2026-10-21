defmodule Palee.Application.GetMyTrainingDepth do
  @moduledoc """
  `GET /api/me/progress/depth` (ADR-165): the member's own muscle coverage
  summary, qualities radar and training load across every provider, for the
  fixed Πρόοδος slots. Takes the Πρόοδος filter (`range`, `sources`; the
  exercise filter does not narrow these sections). Account-level and
  ungated like the account Πρόοδος: it is the member's own data.
  """

  alias Palee.Analytics
  alias Palee.Application.TrainingDepth

  def call(context, params, today \\ Date.utc_today()) do
    with {:ok, filter} <- Analytics.parse_progress_filter(Map.take(params, ["range", "sources"])) do
      {:ok,
       context
       |> TrainingDepth.build(filter.range, today, sources: filter.sources)
       |> Map.put(:sources, filter.sources)}
    end
  end
end
