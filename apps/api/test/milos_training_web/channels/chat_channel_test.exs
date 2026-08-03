defmodule MilosTrainingWeb.ChatChannelTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures
  import Phoenix.ChannelTest

  alias MilosTraining.Application.GetOrCreateMessagingThread
  alias MilosTrainingWeb.{ChatChannel, UserSocket}

  test "a foreign assignment id cannot be used to join its channel" do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})
    outsider = user_fixture(%{role: :athlete})
    workout = workout_fixture(admin)

    {:ok, assignment} =
      MilosTraining.Workouts.assign_workout(%{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: Date.utc_today()
      })

    {:ok, thread} =
      GetOrCreateMessagingThread.call(athlete, %{
        context_type: :assignment,
        context_id: assignment.id
      })

    {:ok, outsider_context} =
      MilosTraining.Organizations.resolve_tenant_context(
        outsider,
        MilosTraining.Organizations.legacy_organization_slug()
      )

    outsider_socket =
      socket(UserSocket, "user:#{outsider.id}", %{
        current_user: outsider,
        tenant_context: outsider_context
      })

    assert {:error, %{reason: "forbidden"}} =
             subscribe_and_join(
               outsider_socket,
               ChatChannel,
               "chat:#{outsider_context.organization_id}:thread:#{thread.id}"
             )
  end

  test "typing and read commands use stable acknowledged payloads" do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})

    {:ok, thread} =
      GetOrCreateMessagingThread.call(admin, %{context_type: :direct, participant_id: athlete.id})

    {:ok, admin_context} =
      MilosTraining.Organizations.resolve_tenant_context(
        admin,
        MilosTraining.Organizations.legacy_organization_slug()
      )

    {:ok, athlete_context} =
      MilosTraining.Organizations.resolve_tenant_context(
        athlete,
        MilosTraining.Organizations.legacy_organization_slug()
      )

    admin_socket =
      socket(UserSocket, "user:#{admin.id}", %{
        current_user: admin,
        tenant_context: admin_context
      })

    athlete_socket =
      socket(UserSocket, "user:#{athlete.id}", %{
        current_user: athlete,
        tenant_context: athlete_context
      })

    {:ok, _, admin_socket} =
      subscribe_and_join(
        admin_socket,
        ChatChannel,
        "chat:#{admin_context.organization_id}:thread:#{thread.id}"
      )

    {:ok, _, _athlete_socket} =
      subscribe_and_join(
        athlete_socket,
        ChatChannel,
        "chat:#{athlete_context.organization_id}:thread:#{thread.id}"
      )

    ref = Phoenix.ChannelTest.push(admin_socket, "typing_start", %{})
    assert_reply ref, :ok, %{typing: true}
    assert_broadcast "typing", %{user_id: user_id, nickname: nickname, typing: true}
    assert user_id == admin.id
    assert nickname == admin.nickname

    operation_id = Ecto.UUID.generate()

    ref =
      Phoenix.ChannelTest.push(admin_socket, "send_message", %{
        "body" => "acknowledged",
        "client_operation_id" => operation_id
      })

    assert_reply ref, :ok, %{id: message_id}, 1_000

    replay_ref =
      Phoenix.ChannelTest.push(admin_socket, "send_message", %{
        "body" => "acknowledged",
        "client_operation_id" => operation_id
      })

    assert_reply replay_ref, :ok, %{id: ^message_id}, 1_000

    ref = Phoenix.ChannelTest.push(admin_socket, "mark_read", %{"message_id" => message_id})
    assert_reply ref, :ok, %{read: true, message_id: ^message_id}
  end
end
