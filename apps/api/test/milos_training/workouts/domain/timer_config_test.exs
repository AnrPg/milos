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

  describe "emom scoring_mode" do
    test "accepts all valid scoring modes" do
      base = %{"type" => "emom", "duration_seconds" => 600, "interval_seconds" => 60}

      for mode <- ~w(for_time for_quality amrap to_failure) do
        assert {:ok, config} = TimerConfig.normalize(Map.put(base, "scoring_mode", mode))
        assert config.scoring_mode == mode
      end
    end

    test "rejects unknown scoring mode" do
      base = %{"type" => "emom", "duration_seconds" => 600, "interval_seconds" => 60}
      assert {:error, reason} = TimerConfig.normalize(Map.put(base, "scoring_mode", "banana"))
      assert reason =~ "scoring_mode"
    end

    test "allows missing scoring_mode (defaults to nil)" do
      assert {:ok, config} =
               TimerConfig.normalize(%{
                 "type" => "emom",
                 "duration_seconds" => 600,
                 "interval_seconds" => 60
               })
      refute Map.has_key?(config, :scoring_mode)
    end

    test "accepts max_windows for to_failure mode" do
      assert {:ok, config} =
               TimerConfig.normalize(%{
                 "type" => "emom",
                 "duration_seconds" => 600,
                 "interval_seconds" => 60,
                 "scoring_mode" => "to_failure",
                 "max_windows" => 50
               })
      assert config.max_windows == 50
    end

    test "ignores amrap_scoring_style on emom type" do
      assert {:ok, _} =
               TimerConfig.normalize(%{
                 "type" => "emom",
                 "duration_seconds" => 600,
                 "interval_seconds" => 60,
                 "amrap_scoring_style" => "invalid_value"
               })
    end
  end

  describe "complex_emom scoring_mode and amrap_scoring_style" do
    test "accepts amrap_scoring_style values" do
      base = %{
        "type" => "complex_emom",
        "duration_seconds" => 600,
        "interval_seconds" => 60,
        "scoring_mode" => "amrap"
      }

      for style <- ~w(grand_total lowest_window) do
        assert {:ok, config} = TimerConfig.normalize(Map.put(base, "amrap_scoring_style", style))
        assert config.amrap_scoring_style == style
      end
    end

    test "rejects invalid amrap_scoring_style" do
      assert {:error, reason} =
               TimerConfig.normalize(%{
                 "type" => "complex_emom",
                 "duration_seconds" => 600,
                 "interval_seconds" => 60,
                 "amrap_scoring_style" => "biggest_number"
               })
      assert reason =~ "amrap_scoring_style"
    end

    test "allows missing amrap_scoring_style" do
      assert {:ok, _config} =
               TimerConfig.normalize(%{
                 "type" => "complex_emom",
                 "duration_seconds" => 600,
                 "interval_seconds" => 60
               })
    end

    test "accepts max_windows for complex_emom" do
      assert {:ok, config} =
               TimerConfig.normalize(%{
                 "type" => "complex_emom",
                 "duration_seconds" => 600,
                 "interval_seconds" => 60,
                 "scoring_mode" => "to_failure",
                 "max_windows" => 15
               })
      assert config.max_windows == 15
    end

    test "rejects invalid scoring_mode on complex_emom" do
      assert {:error, reason} =
               TimerConfig.normalize(%{
                 "type" => "complex_emom",
                 "duration_seconds" => 600,
                 "interval_seconds" => 60,
                 "scoring_mode" => "unknown_mode"
               })
      assert reason =~ "scoring_mode"
    end
  end
end
