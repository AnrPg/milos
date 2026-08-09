defmodule MilosTrainingWeb.ChatChannelTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures
  import Phoenix.ChannelTest

  alias MilosTraining.Application.GetOrCreateMessagingThread
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.{Messaging, Organizations}
  alias MilosTrainingWeb.{ChatChannel, UserSocket}

  defp tenant_context_fixture(owner, name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    context
  end

  defp add_member(organization_id, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization_id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    :ok
  end

  test "a foreign assignment id cannot be used to join its channel" do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})
    outsider = user_fixture(%{role: :athlete})

    context = tenant_context_fixture(admin, "Chat Channel Assignment Gym")
    :ok = add_member(context.organization_id, athlete, :athlete)
    :ok = add_member(context.organization_id, outsider, :athlete)

    {:ok, outsider_context} =
      Organizations.resolve_tenant_context(outsider, context.organization.slug)

    workout = RepoContext.run(context, fn -> workout_fixture(admin) end)

    {:ok, assignment} =
      MilosTraining.Workouts.assign_workout(context, %{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: Date.utc_today()
      })

    {:ok, thread} =
      Messaging.with_tenant_context(context, fn ->
        GetOrCreateMessagingThread.call(athlete, %{
          context_type: :assignment,
          context_id: assignment.id
        })
      end)

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

    admin_context = tenant_context_fixture(admin, "Chat Channel Typing Gym")
    :ok = add_member(admin_context.organization_id, athlete, :athlete)

    {:ok, athlete_context} =
      Organizations.resolve_tenant_context(athlete, admin_context.organization.slug)

    {:ok, thread} =
      Messaging.with_tenant_context(admin_context, fn ->
        GetOrCreateMessagingThread.call(admin, %{
          context_type: :direct,
          participant_id: athlete.id
        })
      end)

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
