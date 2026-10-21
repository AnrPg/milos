defmodule Palee.FakeSpeechTranscriber do
  @moduledoc """
  Test stand-in behind the `SpeechTranscriber` port (ADR-175). Tells the
  calling process what it got (`{:speech_transcriber_called, clip,
  options}`). The transcript is whatever the test put under
  `Process.put(:fake_transcript, text)`, else a fixed Greek sentence;
  `{:error, reason}` there answers that error. Meters one call like a real
  adapter, so the daily cap can be exercised.
  """

  @behaviour Palee.VoiceLog.Ports.SpeechTranscriber

  alias Palee.AiUsage
  alias Palee.AiUsage.Domain.TokenUsage

  @default "Έκανα 5 σετ των 5 back squat με 100 κιλά και 20 λεπτά κωπηλατική."

  def default_transcript, do: @default

  @impl true
  def transcribe(clip, options) do
    send(self(), {:speech_transcriber_called, clip, options})

    case Process.get(:fake_transcript, @default) do
      {:error, _reason} = error ->
        error

      text ->
        AiUsage.report_generation(
          %TokenUsage{
            input_tokens: 400,
            cached_input_tokens: 0,
            output_tokens: 40,
            thinking_tokens: 0
          },
          5,
          options
          |> AiUsage.metering()
          |> Map.merge(%{
            provider: "gemini",
            model: "gemini-2.5-flash",
            model_version: "gemini-2.5-flash",
            agent: "voice_transcribe",
            occurred_at: DateTime.utc_now()
          })
        )

        {:ok, text}
    end
  end
end
