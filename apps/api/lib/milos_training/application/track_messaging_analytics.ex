defmodule MilosTraining.Application.TrackMessagingAnalytics do
  @moduledoc """
  Messaging analytics (ADR-113), applied to the result of a messaging write
  and returning that result unchanged so call sites stay one pipe long.

  * `{:ok, %Thread{}}` - `messaging_thread_created`, once per thread (the
    event dedupes on the thread id and uses the thread's own creator and
    creation time, so get-or-create calls on an existing thread add nothing).
  * `{:ok, %Message{}}` - `messaging_message_sent` (type only, never the
    body) and, when a staff member answers a run of member messages,
    `messaging_first_staff_response` with the response latency.

  Analytics never changes the outcome: any failure here is swallowed.
  """

  alias MilosTraining.Application.{TenantStaffRecipients, TrackAnalyticsEvent}
  alias MilosTraining.Messaging

  @history_limit 50

  def call({:ok, %{sender_id: _, thread_id: _} = message} = result) do
    track_message(message)
    result
  end

  def call({:ok, %{created_by_id: _} = thread} = result) do
    TrackAnalyticsEvent.call("messaging_thread_created", nil, thread, %{
      user_id: thread.created_by_id,
      occurred_at: thread.inserted_at,
      metadata: %{participant_count: participant_count(thread)}
    })

    result
  end

  def call(result), do: result

  defp track_message(message) do
    staff_ids = TenantStaffRecipients.user_ids([message])
    staff? = message.sender_id in staff_ids

    TrackAnalyticsEvent.call("messaging_message_sent", nil, message, %{
      user_id: message.sender_id,
      metadata: %{sender_is_staff: staff?}
    })

    if staff?, do: track_first_staff_response(message, staff_ids)
    :ok
  rescue
    _error -> :ok
  end

  defp track_first_staff_response(message, staff_ids) do
    history =
      Messaging.with_tenant_context(
        %{organization_id: message.organization_id, user_id: message.sender_id},
        fn ->
          Messaging.list_messages(message.thread_id, %{
            actor_id: message.sender_id,
            limit: @history_limit
          })
        end
      )

    with {:ok, messages} <- history,
         %{} = facts <- Messaging.first_staff_response_facts(messages, message, staff_ids) do
      TrackAnalyticsEvent.call("messaging_first_staff_response", nil, message, %{
        user_id: message.sender_id,
        metadata: facts
      })
    end
  end

  defp participant_count(%{participants: participants}) when is_list(participants),
    do: length(participants)

  defp participant_count(_thread), do: nil
end
