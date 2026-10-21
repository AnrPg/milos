defmodule Palee.Infrastructure.Workouts.GeminiWorkoutTextAnalyzerTest do
  use ExUnit.Case, async: false

  alias Palee.Infrastructure.Workouts.GeminiWorkoutTextAnalyzer

  setup do
    previous = Application.get_env(:palee, :gemini)

    Application.put_env(:palee, :gemini,
      api_key: "test-key",
      model: "test-model",
      req_options: [plug: {Req.Test, __MODULE__}, retry: false]
    )

    on_exit(fn -> Application.put_env(:palee, :gemini, previous) end)
  end

  for status <- [402, 429] do
    test "HTTP #{status} from Gemini is reported as exhausted quota, not a generic outage" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(unquote(status))
        |> Req.Test.json(%{"error" => %{"code" => unquote(status), "message" => "credits"}})
      end)

      assert {:error, :analyzer_quota_exhausted} =
               GeminiWorkoutTextAnalyzer.parse("Run 5k", %{locale: "en"})
    end
  end

  test "other upstream failures stay a generic outage" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => %{"code" => 500}})
    end)

    assert {:error, :analyzer_unavailable} =
             GeminiWorkoutTextAnalyzer.parse("Run 5k", %{locale: "en"})
  end
end
