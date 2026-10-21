defmodule Palee.VoiceLog.Ports.LogDraftParser do
  @moduledoc """
  Reads a spoken workout description into a draft training-log entry
  (ADR-175). Provider-agnostic; the answer is untrusted and validated by
  `VoiceLog.Domain.Draft`.

  `input`: `%{transcript: text, locale: "el" | ...}`.

  `options`:
    * `:api_key` – the gym's own key (required);
    * `:model` – the model to call (adapter default otherwise);
    * `:metering` – the ADR-152 metering context, forwarded to `AiUsage`.

  The raw answer: `%{"title", "duration_minutes", "perceived_effort",
  "days_ago", "notes", "exercises" => [%{"name", "sets", "reps", "load",
  "load_unit"}]}`, every value nullable.
  """

  @type error ::
          :parser_not_configured
          | :parser_key_rejected
          | :parser_unavailable
          | :parser_refused
          | :parser_invalid_response

  @callback parse(input :: map(), options :: map()) :: {:ok, map()} | {:error, error()}
end
