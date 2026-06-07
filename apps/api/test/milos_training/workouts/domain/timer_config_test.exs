defmodule MilosTraining.Workouts.Domain.TimerConfigTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Workouts.Domain.TimerConfig

  test "amrap requires duration_seconds" do
    assert {:error, _} = TimerConfig.normalize(%{"type" => "amrap"})

    assert {:ok, %{type: "amrap", duration_seconds: 720}} =
             TimerConfig.normalize(%{"type" => "amrap", "duration_seconds" => 720})
  end

  test "tabata requires work_seconds, rest_seconds, rounds" do
    assert {:error, _} = TimerConfig.normalize(%{"type" => "tabata", "work_seconds" => 20})

    assert {:ok, %{type: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 8}} =
             TimerConfig.normalize(%{
               "type" => "tabata",
               "work_seconds" => 20,
               "rest_seconds" => 10,
               "rounds" => 8
             })
  end

  test "accepts all 18 format types" do
    types_with_params = [
      {"untimed", %{}},
      {"for_time", %{}},
      {"train_to_exhaustion", %{}},
      {"kcal_target", %{"kcal_target" => 100}},
      {"emom", %{"duration_seconds" => 600, "interval_seconds" => 60}},
      {"complex_emom", %{"duration_seconds" => 600, "interval_seconds" => 60}},
      {"even_odd", %{"duration_seconds" => 600}},
      {"billat", %{"work_seconds" => 30, "rest_seconds" => 30, "cycles" => 8}},
      {"amrap", %{"duration_seconds" => 720}},
      {"edt", %{"duration_seconds" => 900}},
      {"death_by", %{"start_reps" => 1, "step_reps" => 1}},
      {"tabata", %{"work_seconds" => 20, "rest_seconds" => 10, "rounds" => 8}},
      {"custom_hiit", %{"work_seconds" => 40, "rest_seconds" => 20, "rounds" => 10}},
      {"cluster", %{"intra_rest_seconds" => 15, "sets" => 5}},
      {"hrr", %{"effort_seconds" => 30}},
      {"ladder_ascending", %{"start_reps" => 1, "step_reps" => 1}},
      {"ladder_descending", %{"start_reps" => 10, "step_reps" => 1, "min_reps" => 1}},
      {"pyramid", %{"peak_reps" => 10, "step_reps" => 2}},
      {"rest", %{"duration_seconds" => 60}}
    ]

    for {type, params} <- types_with_params do
      assert {:ok, _} = TimerConfig.normalize(Map.put(params, "type", type)),
             "expected #{type} to be valid"
    end
  end

  test "rejects unknown format type" do
    assert {:error, "has unsupported timer type"} =
             TimerConfig.normalize(%{"type" => "foobar"})
  end
end
