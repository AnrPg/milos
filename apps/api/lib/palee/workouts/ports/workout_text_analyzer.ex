defmodule Palee.Workouts.Ports.WorkoutTextAnalyzer do
  @moduledoc """
  Port for the workout assistant agents.

    * `outline/2` (step 1) returns `%{"sections" => [%{"name", "format",
      "evidence"}]}`: the workout's structure, validated against
      `FormatSchema.outline_schema/0` by the caller.
    * `parse/2` (step 2) returns the parser agent's untrusted reading of a free-text
      workout (validated by `WorkoutAssistant.Contract` and normalized by
      `FreeTextAnalysis`). With `options.repair = %{previous, violations}` the
      agent is asked to fix its previous answer. With `options.outline` (the
      verified structure) the agent fills those sections against the JSON
      Schema of each format.
    * `proofread/2` returns `%{"corrections" => [...]}` with verbatim in-line
      text corrections (verified by `WorkoutAssistant.Proofreading`).
  """

  @type options :: %{
          required(:locale) => String.t(),
          optional(:repair) => %{previous: map(), violations: [map()]},
          optional(:outline) => %{String.t() => [map()]}
        }
  @type error ::
          :analyzer_not_configured
          | :analyzer_unavailable
          | :analyzer_quota_exhausted
          | :analyzer_invalid_response

  @callback outline(text :: String.t(), options()) :: {:ok, map()} | {:error, error()}
  @callback parse(text :: String.t(), options()) :: {:ok, map()} | {:error, error()}
  @callback proofread(text :: String.t(), options()) :: {:ok, map()} | {:error, error()}
end
