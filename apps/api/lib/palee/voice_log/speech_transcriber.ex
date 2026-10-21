defmodule Palee.VoiceLog.SpeechTranscriber do
  @moduledoc "Facade over the configured speech-to-text adapter (ADR-175)."

  @behaviour Palee.VoiceLog.Ports.SpeechTranscriber

  defp adapter, do: Application.fetch_env!(:palee, :speech_transcriber)

  @impl true
  def transcribe(clip, options), do: adapter().transcribe(clip, options)
end
