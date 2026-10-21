defmodule Palee.Scaling.Ports.ScalingAdvisor do
  @moduledoc """
  The scaling advisor port (ADR-174): given a programmed workout and an
  athlete's active injuries (`Scaling.Domain.AdvisorInput.build/1`), propose
  per-movement changes with reasons. Provider-agnostic; the answer is
  untrusted and validated by `Scaling.Domain.Advice`.

  `options`:
    * `:api_key` – the gym's own key (required);
    * `:model` – the model to call (adapter default otherwise);
    * `:metering` – the ADR-152 metering context, forwarded to `AiUsage`.

  The raw answer: `%{"summary" => text, "scale_level" => slug | nil,
  "items" => [%{"exercise_id", "change", "suggested", "reason"}]}`.
  """

  @type error ::
          :advisor_not_configured
          | :advisor_key_rejected
          | :advisor_unavailable
          | :advisor_refused
          | :advisor_invalid_response

  @callback suggest(input :: map(), options :: map()) :: {:ok, map()} | {:error, error()}
end
