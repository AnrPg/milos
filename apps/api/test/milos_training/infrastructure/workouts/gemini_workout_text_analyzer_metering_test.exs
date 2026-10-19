defmodule MilosTraining.Infrastructure.Workouts.GeminiWorkoutTextAnalyzerMeteringTest do
  use ExUnit.Case, async: false

  alias MilosTraining.AiUsage
  alias MilosTraining.Infrastructure.Workouts.GeminiWorkoutTextAnalyzer
  alias MilosTraining.TestSupport.TelemetryCapture

  setup do
    previous = Application.get_env(:milos_training, :gemini)

    Application.put_env(:milos_training, :gemini,
      api_key: "test-key",
      model: "gemini-3.8-flash",
      thinking_level: "low",
      parser_thinking_level: "medium",
      req_options: [plug: {Req.Test, __MODULE__}, retry: false]
    )

    on_exit(fn -> Application.put_env(:milos_training, :gemini, previous) end)
    TelemetryCapture.capture([AiUsage.generation_event()])
    :ok
  end

  defp answer(parts, usage) do
    %{
      "candidates" => [%{"content" => %{"role" => "model", "parts" => parts}}],
      "usageMetadata" => usage,
      "modelVersion" => "gemini-3.8-flash-001"
    }
  end

  @metering %{operation_id: "8b3c2a43-3f0c-4a51-9d1e-4f6c1d0e7a11", feature: "workout_free_text"}

  test "reports every billed call of an agent loop, tool rounds included" do
    {:ok, rounds} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(__MODULE__, fn conn ->
      case Agent.get_and_update(rounds, &{&1, &1 + 1}) do
        0 ->
          Req.Test.json(
            conn,
            answer(
              [
                %{
                  "functionCall" => %{
                    "name" => "convert_units",
                    "args" => %{"value" => 1, "from" => "lb", "to" => "kg"}
                  }
                }
              ],
              %{
                "promptTokenCount" => 3_000,
                "candidatesTokenCount" => 20,
                "thoughtsTokenCount" => 150
              }
            )
          )

        _final ->
          Req.Test.json(
            conn,
            answer(
              [%{"text" => ~s({"workout": {"title": "Squats"}, "sections": []})}],
              %{
                "promptTokenCount" => 3_200,
                "cachedContentTokenCount" => 2_048,
                "candidatesTokenCount" => 400,
                "thoughtsTokenCount" => 900
              }
            )
          )
      end
    end)

    assert {:ok, %{"workout" => %{"title" => "Squats"}}} =
             GeminiWorkoutTextAnalyzer.parse("5x5 back squat", %{
               locale: "en",
               metering: @metering
             })

    assert_received {:telemetry_event, [:milos, :ai, :generation], first, first_meta}
    assert_received {:telemetry_event, [:milos, :ai, :generation], second, second_meta}

    assert %{input_tokens: 3_000, cached_input_tokens: 0, output_tokens: 20, thinking_tokens: 150} =
             first

    assert %{
             input_tokens: 1_152,
             cached_input_tokens: 2_048,
             output_tokens: 400,
             thinking_tokens: 900
           } =
             second

    for meta <- [first_meta, second_meta] do
      assert meta.operation_id == @metering.operation_id
      assert meta.feature == "workout_free_text"
      assert meta.agent == "parser"
      assert meta.provider == "gemini"
      assert meta.model == "gemini-3.8-flash"
      assert meta.model_version == "gemini-3.8-flash-001"
      assert %DateTime{} = meta.occurred_at
    end
  end

  test "an answered but unusable call is still metered; a failed request is not" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(
        conn,
        answer([%{"text" => "not json"}], %{
          "promptTokenCount" => 900,
          "candidatesTokenCount" => 5
        })
      )
    end)

    assert {:error, :analyzer_invalid_response} =
             GeminiWorkoutTextAnalyzer.outline("AMRAP 10", %{locale: "en", metering: @metering})

    assert_received {:telemetry_event, _event, %{input_tokens: 900}, %{agent: "structure"}}

    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 503, "unavailable"))

    assert {:error, :analyzer_unavailable} =
             GeminiWorkoutTextAnalyzer.proofread("AMRAP 10", %{locale: "en", metering: @metering})

    refute_received {:telemetry_event, _event, _measurements, _metadata}
  end
end
