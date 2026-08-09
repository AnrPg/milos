defmodule MilosTraining.Application.RealtimeSyncTest do
  use MilosTraining.DataCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{
    AssignWorkout,
    CreateDraftWorkout,
    CreateSeasonalChallenge,
    UpdateAdminSettings,
    UpdateDraftWorkout
  }

  alias MilosTraining.Messaging
  alias MilosTraining.Organizations
  alias MilosTraining.Repo
  alias MilosTraining.Workers.DispatchMessageJob

  setup do
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "user:sync")
    :ok
  end

  test "sending a coaching note via messaging emits landing sync for the athlete" do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})
    context = legacy_tenant_context!(admin, :owner)
    set_legacy_session!(context, admin)

    {:ok, thread} =
      Messaging.get_or_create_thread(%{
        context_type: :direct,
        actor_id: admin.id,
        participant_id: athlete.id
      })

    assert {:ok, message} =
             Messaging.send_message(%{
               thread_id: thread.id,
               sender_id: admin.id,
               body: "Stay sharp on pacing.",
               message_type: :coaching_note
             })

    assert :ok =
             DispatchMessageJob.perform(%Oban.Job{
               args: %{"message_id" => message.id, "organization_id" => thread.organization_id}
             })

    assert_user_syncs([
      %{user_id: athlete.id, scopes: ["landing"], reason: "landing_invalidated"}
    ])
  end

  test "assigning a workout emits assigned workout sync for athletes and admins" do
    admin = admin_fixture(%{nickname: "sync_assign_admin"})
    athlete = user_fixture(%{nickname: "sync_assign_athlete", role: :athlete})
    workout = workout_fixture(admin)
    context = legacy_tenant_context!(admin, :owner)
    add_legacy_membership!(athlete, :athlete)

    assert {:ok, assignment} =
             AssignWorkout.call(context, %{
               master_workout_id: workout.id,
               athlete_ids: [athlete.id],
               scheduled_for: Date.utc_today()
             })

    assert_user_syncs([
      %{
        user_id: admin.id,
        scopes: ["assigned_workouts"],
        reason: "assignment_created",
        payload: %{assignment_id: assignment.id}
      },
      %{
        user_id: athlete.id,
        scopes: ["assigned_workouts"],
        reason: "assignment_created",
        payload: %{assignment_id: assignment.id}
      }
    ])
  end

  test "updating admin settings emits landing sync for users and settings sync for admins" do
    admin = admin_fixture(%{nickname: "sync_settings_admin"})
    athlete = user_fixture(%{nickname: "sync_settings_athlete", role: :athlete})
    context = legacy_tenant_context!(admin, :owner)

    assert {:ok, _settings} =
             UpdateAdminSettings.call(context, %{
               gamification: %{
                 weekly_workout_target: 3,
                 streak_shield_reset_day: 7,
                 leaderboard_enabled: true
               }
             })

    assert_user_syncs([
      %{user_id: admin.id, scopes: ["landing"], reason: "landing_invalidated"},
      %{user_id: athlete.id, scopes: ["landing"], reason: "landing_invalidated"},
      %{user_id: admin.id, scopes: ["admin_settings"], reason: "admin_settings_updated"}
    ])
  end

  test "creating a seasonal challenge emits landing sync for users and challenge sync for admins" do
    admin = admin_fixture(%{nickname: "sync_challenge_admin"})
    athlete = user_fixture(%{nickname: "sync_challenge_athlete", role: :athlete})

    params = %{
      title: "Realtime Week",
      description: "Finish two workouts",
      criteria_type: "workout_count",
      criteria_value: %{count: 2},
      badge_key: "challenge_realtime_week",
      badge_label: "Realtime Week",
      starts_at: Date.utc_today(),
      ends_at: Date.add(Date.utc_today(), 7)
    }

    assert {:ok, challenge} = CreateSeasonalChallenge.call(admin.id, params)

    assert_user_syncs([
      %{user_id: admin.id, scopes: ["landing"], reason: "landing_invalidated"},
      %{user_id: athlete.id, scopes: ["landing"], reason: "landing_invalidated"},
      %{
        user_id: admin.id,
        scopes: ["admin_challenges"],
        reason: "challenge_created",
        payload: %{challenge_id: challenge.id}
      }
    ])
  end

  test "updating a draft emits admin workout sync with editor session metadata" do
    admin = admin_fixture(%{nickname: "sync_draft_admin"})
    editor_session_id = "editor-tab-1"

    assert {:ok, draft} = CreateDraftWorkout.call(admin)

    context = legacy_tenant_context!(admin, :owner)
    set_legacy_session!(context, admin)

    assert {:ok, updated_draft} =
             UpdateDraftWorkout.call(draft.id, %{
               title: "Updated title",
               editor_session_id: editor_session_id,
               expected_source_revision: draft.dsl_source_revision
             })

    assert updated_draft.id == draft.id

    assert_user_syncs([
      %{
        user_id: admin.id,
        scopes: ["admin_workouts"],
        reason: "draft_created",
        payload: %{draft_id: draft.id}
      },
      %{
        user_id: admin.id,
        scopes: ["admin_workouts"],
        reason: "draft_updated",
        payload: %{draft_id: draft.id, editor_session_id: editor_session_id}
      }
    ])
  end

  # Fixtures such as `workout_fixture/1` and `CreateDraftWorkout.call/1` create
  # rows through unscoped command paths, so those rows land under whatever
  # organization the DB column default assigns (the seeded legacy
  # organization) rather than under a freshly created test organization.
  # Reading/mutating them back through tenant-scoped queries therefore
  # requires operating within that same legacy organization's context.
  defp legacy_organization,
    do: Organizations.get_by_slug(Organizations.legacy_organization_slug())

  defp add_legacy_membership!(user, role) do
    organization = legacy_organization()

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    organization
  end

  defp legacy_tenant_context!(user, role) do
    add_legacy_membership!(user, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(user, Organizations.legacy_organization_slug())

    context
  end

  defp set_legacy_session!(context, user) do
    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      context.organization_id
    ])

    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", user.id])
    :ok
  end

  defp assert_user_syncs(expected_events, timeout \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_assert_user_syncs(expected_events, [], deadline)
  end

  defp do_assert_user_syncs(expected_events, received_events, deadline) do
    if all_expected_user_syncs_received?(expected_events, received_events) do
      :ok
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:user_sync, event} when is_map(event) ->
          do_assert_user_syncs(expected_events, [event | received_events], deadline)

        _other ->
          do_assert_user_syncs(expected_events, received_events, deadline)
      after
        remaining ->
          flunk("""
          expected user sync events were not all received
          expected: #{inspect(expected_events)}
          received: #{inspect(Enum.reverse(received_events))}
          """)
      end
    end
  end

  defp all_expected_user_syncs_received?(expected_events, received_events) do
    Enum.all?(expected_events, fn expected_event ->
      Enum.any?(received_events, &user_sync_matches?(&1, expected_event))
    end)
  end

  defp user_sync_matches?(received_event, expected_event) do
    Enum.all?(expected_event, fn
      {:payload, expected_payload} ->
        payload = Map.get(received_event, :payload, %{})
        is_map(payload) and Map.take(payload, Map.keys(expected_payload)) == expected_payload

      {key, expected_value} ->
        Map.get(received_event, key) == expected_value
    end)
  end
end
