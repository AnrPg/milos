defmodule MilosTraining.Infrastructure.Ai.GeminiSpeechTranscriber do
  @moduledoc """
  Speech to text on Gemini (ADR-175): one `generateContent` call with the
  clip inline (never uploaded to the Files API, so nothing is stored on the
  provider side) and a fixed instruction to transcribe verbatim.

  The Claude API takes no audio, so transcription uses the platform's
  Gemini key (`GEMINI_API_KEY`) and `GEMINI_TRANSCRIBE_MODEL`
  (`gemini-2.5-flash`); without a key it answers
  `{:error, :transcriber_not_configured}`. The call is metered for the gym
  like any other (ADR-152). The audio and the transcript are never logged.
  """

  @behaviour MilosTraining.VoiceLog.Ports.SpeechTranscriber

  require Logger

  alias MilosTraining.AiUsage

  @endpoint "https://generativelanguage.googleapis.com/v1beta/models"
  @default_model "gemini-2.5-flash"

  @instructions """
  Transcribe the speech in the audio verbatim, in the language spoken.
  Write numbers as digits. Output only the transcript, with no comments,
  labels or translation. If there is no intelligible speech, output nothing.
  """

  @impl true
  def transcribe(clip, options) do
    config = Application.get_env(:milos_training, :gemini, [])

    case Keyword.get(config, :api_key) do
      key when is_binary(key) and key != "" ->
        model = Keyword.get(config, :transcribe_model) || @default_model
        request(key, model, config, clip, AiUsage.metering(options))

      _missing ->
        {:error, :transcriber_not_configured}
    end
  end

  @doc "The request body (exposed for tests)."
  def body(clip) do
    hint =
      case Map.get(clip, :locale) do
        locale when is_binary(locale) -> "Expected language (hint only): #{locale}."
        _none -> "Detect the language."
      end

    %{
      systemInstruction: %{parts: [%{text: @instructions}]},
      contents: [
        %{
          role: "user",
          parts: [
            %{inlineData: %{mimeType: clip.mime_type, data: Base.encode64(clip.audio)}},
            %{text: hint}
          ]
        }
      ],
      generationConfig: %{temperature: 0, thinkingConfig: %{thinkingBudget: 0}}
    }
  end

  defp request(key, model, config, clip, metering) do
    started = System.monotonic_time(:millisecond)

    response =
      Req.post(
        [
          url: "#{@endpoint}/#{model}:generateContent",
          json: body(clip),
          headers: [{"x-goog-api-key", key}],
          receive_timeout: 45_000,
          retry: false
        ]
        |> Keyword.merge(Keyword.get(config, :req_options, []))
      )

    meter(response, model, metering, System.monotonic_time(:millisecond) - started)
    interpret(response)
  end

  defp interpret({:ok, %Req.Response{status: 200, body: %{"candidates" => [candidate | _]}}}) do
    case candidate do
      %{"content" => %{"parts" => parts}} when is_list(parts) ->
        {:ok, parts |> Enum.map(&Map.get(&1, "text", "")) |> Enum.join() |> String.trim()}

      %{"finishReason" => reason} when reason in ["SAFETY", "PROHIBITED_CONTENT"] ->
        {:error, :transcriber_refused}

      _empty ->
        {:ok, ""}
    end
  end

  defp interpret({:ok, %Req.Response{status: 200, body: %{"promptFeedback" => %{}}}}),
    do: {:error, :transcriber_refused}

  defp interpret({:ok, %Req.Response{status: status}}) do
    Logger.info("speech_transcriber_unavailable status=#{status}")
    {:error, :transcriber_unavailable}
  end

  defp interpret({:error, reason}) do
    Logger.info("speech_transcriber_unavailable reason=#{inspect(reason)}")
    {:error, :transcriber_unavailable}
  end

  defp meter({:ok, %Req.Response{status: 200, body: %{} = body}}, model, metering, ms) do
    case AiUsage.token_usage_from_gemini(Map.get(body, "usageMetadata")) do
      nil ->
        :ok

      usage ->
        AiUsage.report_generation(
          usage,
          ms,
          metering
          |> AiUsage.metering_context()
          |> Map.merge(%{
            provider: "gemini",
            model: model,
            model_version: Map.get(body, "modelVersion"),
            agent: "voice_transcribe",
            occurred_at: DateTime.utc_now()
          })
        )
    end
  end

  defp meter(_response, _model, _metering, _ms), do: :ok
end
