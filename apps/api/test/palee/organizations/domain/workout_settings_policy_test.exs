defmodule Palee.Organizations.Domain.WorkoutSettingsPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.WorkoutSettingsPolicy
  alias Palee.Workouts.Domain.WorkoutType

  describe "ADR-275: workout kinds" do
    test "every kind is offered until the gym chooses" do
      settings = WorkoutSettingsPolicy.from_settings(%{})
      assert settings.workout_types == nil
      assert WorkoutSettingsPolicy.workout_types(settings) == WorkoutType.keys()
    end

    test "a choice is stored in catalogue order and read back" do
      current = WorkoutSettingsPolicy.from_settings(%{})

      assert {:ok, stored, updated} =
               WorkoutSettingsPolicy.update(current, %{"workout_types" => ["dance", "crossfit"]})

      assert stored["workout_types"] == ["crossfit", "dance"]
      assert updated.workout_types == ["crossfit", "dance"]
      # The other settings keep their values.
      assert stored["wod_assistant_enabled"] == true

      read = WorkoutSettingsPolicy.from_settings(%{"workouts" => stored})
      assert WorkoutSettingsPolicy.workout_types(read) == ["crossfit", "dance"]
    end

    test "nil clears the choice; an empty or unknown list is refused" do
      current = %{WorkoutSettingsPolicy.defaults() | workout_types: ["crossfit"]}

      assert {:ok, %{"workout_types" => nil}, _} =
               WorkoutSettingsPolicy.update(current, %{workout_types: nil})

      assert {:error, :bad_request} = WorkoutSettingsPolicy.update(current, %{workout_types: []})

      assert {:error, :bad_request} =
               WorkoutSettingsPolicy.update(current, %{workout_types: ["karaoke"]})

      assert {:error, :bad_request} =
               WorkoutSettingsPolicy.update(current, %{workout_types: "yoga"})
    end

    test "kinds the catalogue no longer has are skipped when read" do
      read =
        WorkoutSettingsPolicy.from_settings(%{"workouts" => %{"workout_types" => ["karaoke"]}})

      assert read.workout_types == nil

      read =
        WorkoutSettingsPolicy.from_settings(%{
          "workouts" => %{"workout_types" => ["karaoke", "yoga"]}
        })

      assert read.workout_types == ["yoga"]
    end
  end
end
