defmodule Palee.VoiceLog.Ports.SpeechTranscriber do
  @moduledoc """
  Speech to text for voice logging (ADR-175). Provider-agnostic.

  `clip`: `%{audio: bytes, mime_type: type}` (checked by `Domain.Clip`),
  plus `:locale` (the member's UI language, a hint only). The adapter must
  not keep the audio: no file, no log line.

  `options`: `:metering` – the ADR-152 metering context, forwarded to
  `AiUsage`.

  Answers `{:ok, text}` (may be empty for silence) or an error.
  """

  @type error :: :transcriber_not_configured | :transcriber_unavailable | :transcriber_refused

  @callback transcribe(clip :: map(), options :: map()) :: {:ok, String.t()} | {:error, error()}
end
