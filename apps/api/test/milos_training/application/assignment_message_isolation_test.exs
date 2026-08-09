defmodule MilosTraining.Application.AssignmentMessageIsolationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.{Messaging, Organizations}

  import MilosTraining.TestFixtures

  test "direct threads between admin and each athlete are isolated" do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})
    other = user_fixture(%{role: :athlete})

    context = tenant_context_fixture(admin, "Assignment Isolation Gym")

    {:ok, _admin_membership} =
      Organizations.add_membership(%{
        organization_id: context.organization_id,
        user_id: athlete.id,
        role: :athlete,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, _other_membership} =
      Organizations.add_membership(%{
        organization_id: context.organization_id,
        user_id: other.id,
        role: :athlete,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    Messaging.with_tenant_context(context, fn ->
      {:ok, athlete_thread} =
        Messaging.get_or_create_thread(%{
          context_type: :direct,
          actor_id: admin.id,
          participant_id: athlete.id
        })

      {:ok, _message} =
        Messaging.send_message(%{
          thread_id: athlete_thread.id,
          sender_id: admin.id,
          body: "Private note for athlete",
          message_type: :coaching_note
        })

      {:ok, other_thread} =
        Messaging.get_or_create_thread(%{
          context_type: :direct,
          actor_id: admin.id,
          participant_id: other.id
        })

      refute athlete_thread.id == other_thread.id

      {:ok, other_messages} = Messaging.list_messages(other_thread.id, %{})
      assert other_messages == []

      {:ok, athlete_messages} = Messaging.list_messages(athlete_thread.id, %{})
      assert [%{body: "Private note for athlete"}] = athlete_messages
    end)
  end

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
end
