defmodule Mix.Tasks.Milos.Ai.MeasureFreeTextTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Milos.Ai.MeasureFreeText

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    previous_gemini = Application.get_env(:milos_training, :gemini)
    previous_analyzer = Application.get_env(:milos_training, :workout_text_analyzer)
    previous_shell = Mix.shell()

    Application.put_env(:milos_training, :gemini,
      api_key: "test-key",
      model: "gemini-3.8-flash",
      thinking_level: "low",
      parser_thinking_level: "medium",
      req_options: [plug: {Req.Test, __MODULE__}, retry: false]
    )

    Application.put_env(
      :milos_training,
      :workout_text_analyzer,
      MilosTraining.Infrastructure.Workouts.GeminiWorkoutTextAnalyzer
    )

    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Application.put_env(:milos_training, :gemini, previous_gemini)
      Application.put_env(:milos_training, :workout_text_analyzer, previous_analyzer)
      Mix.shell(previous_shell)
    end)

    # Every agent gets the same well-formed answer and usage report.
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "candidates" => [
          %{
            "content" => %{
              "role" => "model",
              "parts" => [
                %{
                  "text" =>
                    Jason.encode!(%{
                      "sections" => [],
                      "corrections" => [],
                      "workout" => %{"title" => "Sample", "type" => "strength"},
                      "issues" => [],
                      "missing_fields" => []
                    })
                }
              ]
            }
          }
        ],
        "usageMetadata" => %{
          "promptTokenCount" => 1_000,
          "candidatesTokenCount" => 100,
          "thoughtsTokenCount" => 100
        },
        "modelVersion" => "gemini-3.8-flash-001"
      })
    end)

    samples = Path.join(tmp_dir, "samples.txt")
    File.write!(samples, "5x5 back squat\n\n---\n\nAMRAP 10\n10 burpees\n")
    %{samples: samples, out: Path.join(tmp_dir, "out/result.json")}
  end

  test "measures each sample several times and reports every run and its statistics", %{
    samples: samples,
    out: out
  } do
    MeasureFreeText.run([samples, "--runs", "2", "--priced-at", "2026-10-17", "--out", out])

    document = out |> File.read!() |> Jason.decode!()
    assert [first, second] = document["samples"]
    assert first["title"] == "5x5 back squat"
    assert second["title"] == "AMRAP 10"

    for sample <- document["samples"], run <- sample["runs"] do
      assert run["status"] == "ok"
      assert run["calls"] >= 3
      assert run["calls"] == length(run["call_details"])
      # 1000 in × 750 + 200 out × 3750 nano-USD per call
      assert run["cost_nano_usd"] == run["calls"] * 1_500_000
    end

    assert document["overall"]["cost_usd"]["n"] == 4
    assert is_number(document["overall"]["cost_usd"]["mean"])

    assert_received {:mix_shell, :info, ["\nAll 4 runs\n" <> _statistics]}
  end

  test "refuses to run without a key" do
    Application.put_env(:milos_training, :gemini, api_key: nil)

    assert_raise Mix.Error, ~r/GEMINI_API_KEY is not set/, fn ->
      MeasureFreeText.run(["--runs", "1"])
    end
  end
end
