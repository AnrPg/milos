defmodule MilosTraining.Application.MessagingAnalyticsInstrumentationTest do
  @moduledoc "ADR-113: thread created, message sent and first staff response events."
  use MilosTraining.DataCase, async: false

  import MilosTraining.AnalyticsHelpers

  alias MilosTraining.Application.{GetOrCreateMessagingThread, SendMessage}
  alias MilosTraining.{Messaging, Organizations}

  # MessagingController runs every action inside the caller's tenant session.
  defp send!(user, organization, thread, body) do
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)

    {:ok, message} =
      Messaging.with_tenant_context(context, fn ->
        SendMessage.call(user, %{
          thread_id: thread.id,
          sender_id: user.id,
          body: body,
          message_type: :chat
        })
      end)

    message
  end

  defp get_or_create(context, user, params),
    do:
      Messaging.with_tenant_context(context, fn ->
        GetOrCreateMessagingThread.call(context, user, params)
      end)

  test "records thread creation once, message types without bodies, and staff response latency" do
    {organization, owner, _context} = organization_fixture()
    {member, member_context} = member_context(organization)

    params = %{context_type: :direct, participant_id: owner.id}
    assert {:ok, thread} = get_or_create(member_context, member, params)
    assert {:ok, same} = get_or_create(member_context, member, params)
    assert same.id == thread.id

    created = analytics_event!(organization.id, "messaging_thread_created")
    assert created.context_id == thread.id
    assert created.user_id == member.id
    assert created.metadata == %{"context_type" => "direct", "participant_count" => 2}

    send!(member, organization, thread, "Can I scale the thrusters?")
    send!(member, organization, thread, "Also, knee is sore")
    reply = send!(owner, organization, thread, "Yes, use 25kg")
    send!(owner, organization, thread, "And skip the jumps")

    sent = analytics_events(organization.id, "messaging_message_sent")
    assert length(sent) == 4

    for event <- sent do
      assert event.metadata["message_type"] == "chat"
      assert event.metadata["thread_id"] == thread.id
      refute Map.has_key?(event.metadata, "body")
    end

    assert Enum.count(sent, & &1.metadata["sender_is_staff"]) == 2

    response = analytics_event!(organization.id, "messaging_first_staff_response")
    assert response.context_id == reply.id
    assert response.user_id == owner.id
    assert response.metadata["pending_member_message_count"] == 2
    assert response.metadata["response_latency_seconds"] >= 0

    send!(member, organization, thread, "Thanks!")
    send!(owner, organization, thread, "Anytime")
    assert length(analytics_events(organization.id, "messaging_first_staff_response")) == 2
  end
end
