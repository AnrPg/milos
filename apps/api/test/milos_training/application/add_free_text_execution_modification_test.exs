defmodule MilosTraining.Application.AddFreeTextExecutionModificationTest do
  use MilosTraining.DataCase, async: true

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.AddExecutionModifications
  alias MilosTraining.Execution

  test "persists a free-text modification as one multiline execution patch" do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})

    workout = workout_fixture(admin)

    assert {:ok, execution} =
             Execution.start_execution(athlete.id, %{
               master_workout_id: workout.id,
               source: :self_selected,
               timezone: "UTC"
             })

    note = "Used a lighter sandbag.\nStopped after four rounds."

    assert {:ok, updated} =
             AddExecutionModifications.call(execution.id, athlete.id, [
               %{
                 "patch_id" => "free-text:modification",
                 "type" => "other",
                 "field" => "note",
                 "section_id" => "free_text",
                 "canonical_value" => "",
                 "actual_value" => note
               }
             ])

    assert [%{"actual_value" => ^note, "field" => "note"}] = updated.exercise_modifications

    assert [%{"actual_value" => ^note}] =
             Execution.get_execution(execution.id).exercise_modifications
  end
end
