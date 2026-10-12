defmodule MilosTraining.Application.WorkoutAnalyticsInstrumentationTest do
  @moduledoc "ADR-123: workout authoring and assignment lifecycle events."
  use MilosTraining.DataCase, async: false

  import MilosTraining.AnalyticsHelpers

  alias MilosTraining.Application.{
    AssignWorkout,
    CreateDraftWorkout,
    DeleteAssignedWorkout,
    DeleteWorkout,
    DuplicateWorkout,
    OpenAssignedWorkout,
    PublishWorkout,
    RejectAssignedWorkout,
    RescheduleAssignedWorkout,
    UpdateDraftWorkout
  }

  alias MilosTraining.TestFixtures

  defp draft_payload do
    %{
      "title" => "Engine #{System.unique_integer([:positive])}",
      "type" => "crossfit",
      "expected_source_revision" => 0,
      "sections" => [
        %{
          "name" => "Main",
          "order" => 1,
          "exercises" => [
            %{
              "name" => "Burpees",
              "order" => 1,
              "sets" => 1,
              "prescription_value" => 10,
              "prescription_unit" => "reps"
            }
          ]
        }
      ]
    }
  end

  test "draft creation, first publish, duplication and deletion are recorded" do
    {organization, owner, context} = organization_fixture()

    assert {:ok, draft} = CreateDraftWorkout.call(context, owner)
    created = analytics_event!(organization.id, "workout_created")
    assert created.context_id == draft.id
    assert created.user_id == owner.id
    assert created.actor_role_snapshot == "owner"
    assert created.metadata["status"] == "draft"

    assert {:ok, _draft} = UpdateDraftWorkout.call(context, draft.id, draft_payload())

    assert {:ok, workout} =
             PublishWorkout.call(context, draft.id, %{"expected_source_revision" => 1})

    published = analytics_event!(organization.id, "workout_published")
    assert published.context_type == "workout"
    assert published.context_id == workout.id
    assert published.metadata["type"] == "crossfit"
    assert published.metadata["affected_assignment_count"] == 0
    assert analytics_events(organization.id, "workout_republished") == []

    assert {:ok, copy} = DuplicateWorkout.call(context, workout.id, [])
    duplicated = analytics_event!(organization.id, "workout_duplicated")
    assert duplicated.context_id == copy.id
    assert duplicated.metadata["source_workout_id"] == workout.id
    assert duplicated.metadata["origin"] == "library"

    assert :ok = DeleteWorkout.call(context, workout.id)
    deleted = analytics_event!(organization.id, "workout_deleted")
    assert deleted.context_id == workout.id

    assert Map.keys(deleted.metadata) |> Enum.sort() ==
             ~w(affected_assignment_count affected_booking_count deleted_slot_count)
  end

  test "assignment lifecycle and athlete opens are recorded per tenant" do
    {organization, owner, context} = organization_fixture()
    {athlete, athlete_context} = member_context(organization, :athlete)
    workout = TestFixtures.workout_fixture(owner, %{tenant_context: context})

    assert {:ok, assignment} =
             AssignWorkout.call(context, %{
               master_workout_id: workout.id,
               athlete_ids: [athlete.id],
               scheduled_for: Date.utc_today()
             })

    created = analytics_event!(organization.id, "workout_assignment_created")
    assert created.context_id == assignment.id
    assert created.metadata["athlete_count"] == 1
    assert created.metadata["master_workout_id"] == workout.id

    assert :ok = OpenAssignedWorkout.call(athlete_context, assignment.id)
    assert :ok = OpenAssignedWorkout.call(athlete_context, assignment.id)
    opened = analytics_event!(organization.id, "workout_assignment_opened")
    assert opened.user_id == athlete.id
    assert opened.dedupe_key =~ "#{athlete.id}:#{assignment.id}:"

    # Staff who are not linked to the assignment cannot record an open.
    assert {:error, :not_found} = OpenAssignedWorkout.call(context, assignment.id)
    assert {:error, :not_found} = OpenAssignedWorkout.call(athlete_context, "not-a-uuid")

    tomorrow = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

    assert {:ok, _updated} =
             RescheduleAssignedWorkout.call(athlete_context, assignment.id, athlete.id, tomorrow)

    rescheduled = analytics_event!(organization.id, "workout_assignment_rescheduled")
    assert rescheduled.user_id == athlete.id
    assert rescheduled.metadata["scheduled_for"] == tomorrow

    assert {:ok, _rejected} =
             RejectAssignedWorkout.call(athlete_context, assignment.id, athlete.id)

    assert analytics_event!(organization.id, "workout_assignment_rejected").user_id == athlete.id

    # The rejection reaches the owning tenant's staff (the payload used to
    # carry no organization, so staff recipients resolved to nobody).
    assert Enum.any?(
             MilosTraining.Notifications.list_for_user(owner.id),
             &(&1.type in [:workout_rejected, "workout_rejected"])
           )

    assert :ok = DeleteAssignedWorkout.call(context, assignment.id)
    assert analytics_event!(organization.id, "workout_assignment_deleted").user_id == owner.id
  end
end
