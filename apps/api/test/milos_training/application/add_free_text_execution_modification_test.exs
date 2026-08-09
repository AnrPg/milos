defmodule MilosTraining.Application.AddFreeTextExecutionModificationTest do
  use MilosTraining.DataCase, async: true

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.AddExecutionModifications
  alias MilosTraining.{Execution, Organizations}

  test "persists a free-text modification as one multiline execution patch" do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})

    {:ok, organization} = Organizations.create_organization(%{name: "Free Text Mod Gym"})

    {:ok, _owner_membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: admin.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, _athlete_membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: athlete.id,
        role: :athlete,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)

    # `Execution.start_execution/2` bypasses AuthorizeWorkoutExecutionSource
    # (the HTTP-facing flow), so the tenant scope it would otherwise open
    # around the workout lookup has to be opened here instead - see
    # MilosTraining.Application.StartWorkoutExecution and the RLS policy on
    # master_workouts (F-03/F-04).
    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      context.organization_id
    ])

    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", athlete.id])

    workout = workout_fixture(admin)

    assert {:ok, execution} =
             Execution.start_execution(athlete.id, %{
               organization_id: workout.organization_id,
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
