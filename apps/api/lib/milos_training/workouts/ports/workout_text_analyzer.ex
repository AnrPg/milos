defmodule MilosTraining.Workouts.Ports.WorkoutTextAnalyzer do
  @moduledoc """
  Port for the workout assistant agents.

    * `parse/2` returns the parser agent's untrusted reading of a free-text
      workout (validated by `WorkoutAssistant.Contract` and normalized by
      `FreeTextAnalysis`). With `options.repair = %{previous, violations}` the
      agent is asked to fix its previous answer.
    * `proofread/2` returns `%{"corrections" => [...]}` with verbatim in-line
      text corrections (verified by `WorkoutAssistant.Proofreading`).
  """

  @type options :: %{
          required(:locale) => String.t(),
          optional(:repair) => %{previous: map(), violations: [map()]}
        }
  @type error :: :analyzer_not_configured | :analyzer_unavailable | :analyzer_invalid_response

  @callback parse(text :: String.t(), options()) :: {:ok, map()} | {:error, error()}
  @callback proofread(text :: String.t(), options()) :: {:ok, map()} | {:error, error()}
end
