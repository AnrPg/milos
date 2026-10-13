defmodule MilosTraining.Application.ListCoachingReplyQueue do
  @moduledoc """
  Client messages waiting for a staff reply, with the due time from the
  client's package response time (ADR-098). Overdue items come first.
  """

  alias MilosTraining.{Finance, Identity, Messaging, Organizations}
  alias MilosTraining.Coaching.Domain.ReplyQueuePolicy

  def call(%{organization_id: organization_id} = context, now \\ DateTime.utc_now()) do
    staff_ids = Organizations.list_staff_user_ids(organization_id)
    awaiting = Messaging.list_awaiting_staff_reply(context, staff_ids)
    nicknames = awaiting |> Enum.map(& &1.sender_id) |> nicknames()

    awaiting
    |> Enum.map(fn item ->
      sent_at = to_datetime(item.sent_at)
      hours = sla_hours(context, item.sender_id)
      due_at = ReplyQueuePolicy.due_at(sent_at, hours)

      %{
        thread_id: item.thread_id,
        message_id: item.message_id,
        client_id: item.sender_id,
        client_nickname: Map.get(nicknames, item.sender_id),
        sent_at: sent_at,
        response_sla_hours: hours,
        due_at: due_at
      }
    end)
    |> Enum.map(&Map.put(&1, :overdue, ReplyQueuePolicy.overdue?(&1, now)))
    |> ReplyQueuePolicy.order()
  end

  defp sla_hours(context, user_id) do
    case Finance.get_effective_entitlement(context, user_id) do
      %{plan: %{terms: terms}} -> Map.get(terms, :response_sla_hours)
      _other -> nil
    end
  end

  defp nicknames(ids),
    do: ids |> Enum.uniq() |> Identity.list_by_ids() |> Map.new(&{&1.id, &1.nickname})

  defp to_datetime(%DateTime{} = value), do: value
  defp to_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
end
