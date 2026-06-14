defmodule MilosTraining.Application.AssignmentMessageIsolationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Messaging

  import MilosTraining.TestFixtures

  test "direct threads between admin and each athlete are isolated" do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})
    other = user_fixture(%{role: :athlete})

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
  end
end
