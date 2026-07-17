defmodule MilosTraining.Pantheon.Domain.PRResultMetricsTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Pantheon.Domain.PRResultMetrics

  test "normalizes known typed supporting metrics" do
    assert {:ok, metrics} =
             PRResultMetrics.normalize(%{
               "reps" => "5",
               "sets" => 3,
               "load_kg" => "60.5",
               "duration_seconds" => 91,
               "equipment" => "Barbell",
               "variation" => "Paused"
             })

    assert metrics == %{
             "reps" => 5,
             "sets" => 3,
             "load_kg" => 60.5,
             "duration_seconds" => 91.0,
             "equipment" => "Barbell",
             "variation" => "Paused"
           }
  end

  test "rejects unknown, negative, and blank metrics" do
    assert {:error, [supporting_metrics: "contains an unsupported metric"]} =
             PRResultMetrics.normalize(%{"pace" => 3})

    assert {:error, [supporting_metrics: "must be greater than or equal to zero"]} =
             PRResultMetrics.normalize(%{"reps" => -1})

    assert {:error, [supporting_metrics: "must not include blank text"]} =
             PRResultMetrics.normalize(%{"equipment" => "  "})
  end
end
