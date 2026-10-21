defmodule Palee.Infrastructure.Ai.AnthropicScalingAdvisorTest do
  @moduledoc "ADR-174: the Claude API adapter behind the ScalingAdvisor port (HTTP stubbed)."

  use ExUnit.Case, async: false

  alias Palee.AiUsage
  alias Palee.Infrastructure.Ai.AnthropicScalingAdvisor
  alias Palee.TestSupport.TelemetryCapture

  @input %{locale: "el", workout: %{title: "WOD", sections: []}, injuries: []}
  @metering %{
    operation_id: "8b3c2a43-3f0c-4a51-9d1e-4f6c1d0e7a11",
    feature: "scaling_suggestions",
    organization_id: nil
  }

  setup do
    previous = Application.get_env(:palee, :anthropic)

    Application.put_env(:palee, :anthropic,
      scaling_model: "claude-sonnet-5-5",
      req_options: [plug: {Req.Test, __MODULE__}, retry: false]
    )

    on_exit(fn -> Application.put_env(:palee, :anthropic, previous) end)
    TelemetryCapture.capture([AiUsage.generation_event()])
    :ok
  end

  defp answer(json, extra \\ %{}) do
    Map.merge(
      %{
        "model" => "claude-sonnet-5-5",
        "stop_reason" => "end_turn",
        "content" => [%{"type" => "text", "text" => Jason.encode!(json)}],
        "usage" => %{
          "input_tokens" => 1_000,
          "cache_read_input_tokens" => 200,
          "cache_creation_input_tokens" => 0,
          "output_tokens" => 300
        }
      },
      extra
    )
  end

  test "without a key it does not call out" do
    assert {:error, :advisor_not_configured} = AnthropicScalingAdvisor.suggest(@input, %{})
  end

  test "sends the gym's key, a JSON schema and refusal fallbacks; meters the call" do
    parent = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request, conn.req_headers, Jason.decode!(body)})
      Req.Test.json(conn, answer(%{"summary" => "ok", "scale_level" => nil, "items" => []}))
    end)

    assert {:ok, %{"summary" => "ok", "items" => []}} =
             AnthropicScalingAdvisor.suggest(@input, %{api_key: "gym-key", metering: @metering})

    assert_received {:request, headers, body}
    assert {"x-api-key", "gym-key"} in headers
    assert {"anthropic-version", "2023-06-01"} in headers
    assert {"anthropic-beta", "server-side-fallback-2026-07-01"} in headers
    assert body["model"] == "claude-sonnet-5-5"
    assert body["fallbacks"] == "default"
    assert body["output_config"]["format"]["type"] == "json_schema"
    assert body["output_config"]["effort"] == "low"
    refute Map.has_key?(body, "thinking")
    assert Jason.decode!(hd(body["messages"])["content"])["locale"] == "el"

    assert_received {:telemetry_event, [:palee, :ai, :generation], measurements, metadata}
    assert measurements.input_tokens == 1_000
    assert measurements.cached_input_tokens == 200
    assert measurements.output_tokens == 300
    assert metadata.provider == "anthropic"
    assert metadata.feature == "scaling_suggestions"

    assert {:ok, 5_040_000} =
             AiUsage.cost(
               AiUsage.token_usage_from_anthropic(answer(%{})["usage"]),
               "claude-sonnet-5-5",
               ~D[2026-10-21]
             )
  end

  test "a model override without fallback support sends no fallbacks" do
    parent = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request, conn.req_headers, Jason.decode!(body)})
      Req.Test.json(conn, answer(%{"summary" => "", "scale_level" => nil, "items" => []}))
    end)

    assert {:ok, _} =
             AnthropicScalingAdvisor.suggest(@input, %{api_key: "k", model: "claude-haiku-5-5"})

    assert_received {:request, headers, body}
    refute Map.has_key?(body, "fallbacks")
    refute Enum.any?(headers, fn {name, _} -> name == "anthropic-beta" end)
  end

  test "maps provider failures to port errors" do
    for {status, expected} <- [
          {401, :advisor_key_rejected},
          {403, :advisor_key_rejected},
          {429, :advisor_unavailable},
          {529, :advisor_unavailable}
        ] do
      Req.Test.stub(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{})
      end)

      assert {:error, ^expected} = AnthropicScalingAdvisor.suggest(@input, %{api_key: "k"})
    end

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, answer(%{}, %{"stop_reason" => "refusal", "content" => []}))
    end)

    assert {:error, :advisor_refused} = AnthropicScalingAdvisor.suggest(@input, %{api_key: "k"})

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(
        conn,
        answer(%{}, %{"content" => [%{"type" => "text", "text" => "not json"}]})
      )
    end)

    assert {:error, :advisor_invalid_response} =
             AnthropicScalingAdvisor.suggest(@input, %{api_key: "k"})
  end
end
