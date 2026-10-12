defmodule MilosTraining.Workouts.Ports.WorkoutTextAnalyzer do
  @moduledoc """
  Port for an assistant that reads a coach's free-text workout and returns an
  untrusted interpretation (see `MilosTraining.Workouts.Domain.FreeTextAnalysis`
  for the expected raw shape and how it is validated).
  """

  @type options :: %{required(:locale) => String.t()}

  @callback analyze(text :: String.t(), options()) ::
              {:ok, map()}
              | {:error,
                 :analyzer_not_configured | :analyzer_unavailable | :analyzer_invalid_response}
end
