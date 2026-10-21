defmodule MilosTraining.VoiceLog.SpeechTranscriber do
  @moduledoc "Facade over the configured speech-to-text adapter (ADR-175)."

  @behaviour MilosTraining.VoiceLog.Ports.SpeechTranscriber

  defp adapter, do: Application.fetch_env!(:milos_training, :speech_transcriber)

  @impl true
  def transcribe(clip, options), do: adapter().transcribe(clip, options)
end
