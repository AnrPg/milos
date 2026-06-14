defmodule MilosTraining.Application.WriteAdminAthleteNoteTest do
  use MilosTraining.DataCase

  alias MilosTraining.Messaging
  alias MilosTraining.TestFixtures

  test "sends a coaching_note message and returns it even when notification delivery fails" do
    admin = TestFixtures.admin_fixture()
    athlete = TestFixtures.user_fixture(%{role: :athlete})

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
