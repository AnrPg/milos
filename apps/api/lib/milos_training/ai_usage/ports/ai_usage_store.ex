defmodule MilosTraining.AiUsage.Ports.AiUsageStore do
  @moduledoc "Persistence port of the AI usage context (ADR-152)."

  @type summary_params :: %{
          optional(:from) => DateTime.t(),
          optional(:to) => DateTime.t(),
          optional(:feature) => String.t()
        }

  @callback insert_record(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_operation(map(), binary()) :: [map()]
  @callback summarize(map(), summary_params()) :: [map()]

  # ADR-174: the gym's AI settings row (key encrypted at rest).
  @callback get_settings(map()) :: map() | nil
  @callback put_settings(map(), map()) :: {:ok, map()} | {:error, term()}
end
