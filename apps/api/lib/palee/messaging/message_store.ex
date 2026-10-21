defmodule Palee.Messaging.MessageStore do
  @behaviour Palee.Messaging.Ports.MessageStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  @impl true
  def create_message(attrs), do: impl().create_message(attrs)
  @impl true
  def create_message_with_delivery(attrs, delivery),
    do: impl().create_message_with_delivery(attrs, delivery)

  @impl true
  def list_messages(thread_id, params), do: impl().list_messages(thread_id, params)
  @impl true
  def get_message(id), do: impl().get_message(id)
  @impl true
  def list_recent_coaching_messages(user_id, limit),
    do: impl().list_recent_coaching_messages(user_id, limit)

  @impl true
  def list_recent_coaching_messages_for_organization(user_id, limit),
    do: impl().list_recent_coaching_messages_for_organization(user_id, limit)

  @impl true
  def count_sent(sender_id, message_type, since),
    do: impl().count_sent(sender_id, message_type, since)

  @impl true
  def count_awaiting_reply(coach_id, client_ids),
    do: impl().count_awaiting_reply(coach_id, client_ids)

  @impl true
  def list_awaiting_staff_reply(staff_ids), do: impl().list_awaiting_staff_reply(staff_ids)

  def list_awaiting_staff_reply(context, staff_ids),
    do: RepoContext.run(context, fn -> list_awaiting_staff_reply(staff_ids) end)

  defp impl do
    Application.fetch_env!(:palee, :messaging_message_store)
  end
end
