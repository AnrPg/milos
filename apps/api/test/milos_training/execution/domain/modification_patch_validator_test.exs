defmodule MilosTraining.Execution.Domain.ModificationPatchValidatorTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Execution.Domain.ModificationPatchValidator

  test "normalizes patches for one concrete expanded set row" do
    assert {:ok, [patch]} =
             ModificationPatchValidator.normalize_many([
               %{
                 "patch_id" => "segment:0:squat:2:reps",
                 "section_id" => "section-1",
                 "section_name" => "Strength",
                 "segment_key" => "segment:0",
                 "exercise_id" => "squat",
                 "exercise_name" => "Squat",
                 "set_index" => 2,
                 "field" => "reps",
                 "canonical_value" => 5,
                 "actual_value" => 3
               }
             ])

    assert patch["type"] == "reps_changed"
    assert patch["section_id"] == "section-1"
    assert patch["exercise_id"] == "squat"
    assert patch["set_index"] == 2
    assert patch["canonical_value"] == 5
    assert patch["actual_value"] == 3
    assert patch["patch_id"] == "segment:0:squat:2:reps"
  end

  test "rejects broad or empty modifications" do
    assert {:error, :bad_request} =
             ModificationPatchValidator.normalize_many([
               %{
                 "patch_id" => "missing-section",
                 "exercise_id" => "squat",
                 "field" => "reps",
                 "canonical_value" => 5,
                 "actual_value" => 3
               }
             ])

    assert {:error, :bad_request} =
             ModificationPatchValidator.normalize_many([
               %{
                 "patch_id" => "empty-change",
                 "section_id" => "section-1",
                 "exercise_id" => "squat",
                 "field" => "reps",
                 "canonical_value" => 5,
                 "actual_value" => 5
               }
             ])
  end
end
