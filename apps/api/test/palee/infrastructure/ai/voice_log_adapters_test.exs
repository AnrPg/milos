defmodule Palee.Infrastructure.Ai.VoiceLogAdaptersTest do
  @moduledoc "ADR-175: the Gemini transcriber and the Claude API parser behind the voice-log ports (HTTP stubbed)."

  use ExUnit.Case, async: false

  alias Palee.AiUsage
  alias Palee.Infrastructure.Ai.{AnthropicLogDraftParser, GeminiSpeechTranscriber}
  alias Palee.TestSupport.TelemetryCapture

  @metering %{
    operation_id: "8b3c2a43-3f0c-4a51-9d1e-4f6c1d0e7a11",
    feature: "voice_log",
    organization_id: nil
  }

  setup do
    previous_anthropic = Application.get_env(:palee, :anthropic)
    previous_gemini = Application.get_env(:palee, :gemini)

    Application.put_env(:palee, :anthropic,
      voice_model: "claude-sonnet-5-5",
      req_options: [plug: {Req.Test, __MODULE__}, retry: false]
    )

    Application.put_env(:palee, :gemini,
      api_key: "platform-gemini-key",
      transcribe_model: "gemini-2.5-flash",
      req_options: [plug: {Req.Test, __MODULE__}, retry: false]
    )

    on_exit(fn ->
      Application.put_env(:palee, :anthropic, previous_anthropic)
      Application.put_env(:palee, :gemini, previous_gemini)
    end)

    TelemetryCapture.capture([AiUsage.generation_event()])
    :ok
  end

  describe "GeminiSpeechTranscriber" do
    @clip %{audio: <<1, 2, 3, 4>>, mime_type: "audio/wav", locale: "el"}

    test "sends the clip inline with a verbatim instruction; meters the call" do
      parent = self()

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(parent, {:request, conn.request_path, conn.req_headers, Jason.decode!(body)})

        Req.Test.json(conn, %{
          "modelVersion" => "gemini-2.5-flash-001",
          "candidates" => [%{"content" => %{"parts" => [%{"text" => " 5 γύροι Fran \n"}]}}],
          "usageMetadata" => %{"promptTokenCount" => 500, "candidatesTokenCount" => 20}
        })
      end)

      assert {:ok, "5 γύροι Fran"} =
               GeminiSpeechTranscriber.transcribe(@clip, %{metering: @metering})

      assert_received {:request, path, headers, body}
      assert path =~ "gemini-2.5-flash:generateContent"
      assert {"x-goog-api-key", "platform-gemini-key"} in headers
      [%{"parts" => [%{"inlineData" => inline}, %{"text" => hint}]}] = body["contents"]
      assert inline == %{"mimeType" => "audio/wav", "data" => Base.encode64(<<1, 2, 3, 4>>)}
      assert hint =~ "el"

      assert_received {:telemetry_event, _event, %{input_tokens: 500},
                       %{agent: "voice_transcribe", feature: "voice_log", provider: "gemini"}}
    end

    test "no key → not configured; errors and blocks map to port errors" do
      Application.put_env(:palee, :gemini, api_key: nil)

      assert {:error, :transcriber_not_configured} =
               GeminiSpeechTranscriber.transcribe(@clip, %{})

      Application.put_env(:palee, :gemini,
        api_key: "k",
        req_options: [plug: {Req.Test, __MODULE__}, retry: false]
      )

      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 503, "busy"))
      assert {:error, :transcriber_unavailable} = GeminiSpeechTranscriber.transcribe(@clip, %{})

      Req.Test.stub(
        __MODULE__,
        &Req.Test.json(&1, %{"candidates" => [%{"finishReason" => "SAFETY"}]})
      )

      assert {:error, :transcriber_refused} = GeminiSpeechTranscriber.transcribe(@clip, %{})

      Req.Test.stub(
        __MODULE__,
        &Req.Test.json(&1, %{"candidates" => [%{"finishReason" => "STOP"}]})
      )

      assert {:ok, ""} = GeminiSpeechTranscriber.transcribe(@clip, %{})
    end
  end

  describe "AnthropicLogDraftParser" do
    @input %{transcript: "Fran σε 6 λεπτά", locale: "el"}

    defp answer(json, extra \\ %{}) do
      Map.merge(
        %{
          "model" => "claude-sonnet-5-5",
          "stop_reason" => "end_turn",
          "content" => [%{"type" => "text", "text" => Jason.encode!(json)}],
          "usage" => %{"input_tokens" => 900, "output_tokens" => 120}
        },
        extra
      )
    end

    test "without a key it does not call out" do
      assert {:error, :parser_not_configured} = AnthropicLogDraftParser.parse(@input, %{})
    end

    test "sends the gym's key, only the transcript and locale, a JSON schema; meters the call" do
      parent = self()

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(parent, {:request, conn.req_headers, Jason.decode!(body)})
        Req.Test.json(conn, answer(%{"title" => "Fran", "exercises" => []}))
      end)

      assert {:ok, %{"title" => "Fran"}} =
               AnthropicLogDraftParser.parse(@input, %{api_key: "gym-key", metering: @metering})

      assert_received {:request, headers, body}
      assert {"x-api-key", "gym-key"} in headers
      assert {"anthropic-beta", "server-side-fallback-2026-07-01"} in headers
      assert body["model"] == "claude-sonnet-5-5"
      assert body["fallbacks"] == "default"
      assert body["output_config"]["effort"] == "low"
      assert body["output_config"]["format"]["type"] == "json_schema"

      assert [%{"role" => "user", "content" => content}] = body["messages"]
      assert Jason.decode!(content) == %{"locale" => "el", "transcript" => "Fran σε 6 λεπτά"}

      assert_received {:telemetry_event, _event, %{input_tokens: 900, output_tokens: 120},
                       %{agent: "voice_parse", feature: "voice_log", provider: "anthropic"}}
    end

    test "maps rejections, refusals, outages and bad answers" do
      options = %{api_key: "gym-key", model: "custom-model"}

      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 401, "{}"))
      assert {:error, :parser_key_rejected} = AnthropicLogDraftParser.parse(@input, options)

      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 529, "{}"))
      assert {:error, :parser_unavailable} = AnthropicLogDraftParser.parse(@input, options)

      Req.Test.stub(__MODULE__, &Req.Test.json(&1, answer(%{}, %{"stop_reason" => "refusal"})))
      assert {:error, :parser_refused} = AnthropicLogDraftParser.parse(@input, options)

      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "not json"}]})
      end)

      assert {:error, :parser_invalid_response} = AnthropicLogDraftParser.parse(@input, options)
    end

    test "a custom model gets no fallbacks" do
      refute Map.has_key?(AnthropicLogDraftParser.body("custom-model", @input), :fallbacks)
    end
  end
end
