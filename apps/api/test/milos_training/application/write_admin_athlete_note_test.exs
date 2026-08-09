defmodule MilosTraining.Application.WriteAdminAthleteNoteTest do
  use MilosTraining.DataCase

  alias MilosTraining.{Messaging, Organizations}
  alias MilosTraining.TestFixtures

  setup do
    admin = TestFixtures.admin_fixture()
    athlete = TestFixtures.user_fixture(%{role: :athlete})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Athlete Note Gym #{System.unique_integer([:positive])}"
      })

    {:ok, _admin_membership} =
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

    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      organization.id
    ])

    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", admin.id])

    %{admin: admin, athlete: athlete, organization: organization}
  end

  test "sends a coaching_note message and returns it even when notification delivery fails", %{
    admin: admin,
    athlete: athlete
  } do
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
               body: "Keep the tempo steady.",
               message_type: :coaching_note
             })

    assert message.message_type == :coaching_note
    assert message.sender_id == admin.id
    assert message.body == "Keep the tempo steady."

    {:ok, messages} = Messaging.list_messages(thread.id, %{})
    assert Enum.any?(messages, &(&1.id == message.id))
  end
end
