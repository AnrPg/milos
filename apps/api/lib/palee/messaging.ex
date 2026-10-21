defmodule Palee.Messaging do
  alias Palee.Messaging.Application.{
    GetOrCreateThread,
    SendMessage,
    ListMessages,
    ListThreads,
    MarkRead,
    GetThread
  }

  alias Palee.Messaging.{MessageStore, ThreadStore}

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: ThreadStore.with_tenant_context(context, fun)

  # ADR-123 staff response latency facts.
  defdelegate first_staff_response_facts(messages, new_message, staff_ids),
    to: Palee.Messaging.Domain.ResponseLatency,
    as: :first_staff_response

  defdelegate get_or_create_thread(params), to: GetOrCreateThread, as: :call
  defdelegate send_message(params), to: SendMessage, as: :call
  defdelegate send_message(params, delivery), to: SendMessage, as: :call
  defdelegate list_messages(thread_id, params), to: ListMessages, as: :call
  defdelegate list_threads_for_user(user_id, context_type \\ nil), to: ListThreads, as: :call
  defdelegate mark_read(thread_id, user_id, message_id), to: MarkRead, as: :call
  defdelegate get_thread(thread_id, user_id), to: GetThread, as: :call
  def get_message(message_id), do: Palee.Messaging.MessageStore.get_message(message_id)

  def list_recent_coaching_messages(user_id, limit \\ 5)
      when is_integer(limit) and limit in 1..50,
      do: MessageStore.list_recent_coaching_messages(user_id, limit)

  def list_recent_coaching_messages_for_organization(user_id, limit \\ 5)
      when is_integer(limit) and limit in 1..50,
      do: MessageStore.list_recent_coaching_messages_for_organization(user_id, limit)

  @doc "Messages of one kind a sender wrote since a time (Πελάτες μου stats)."
  def count_sent(sender_id, message_type, %NaiveDateTime{} = since),
    do: MessageStore.count_sent(sender_id, message_type, since)

  @doc "Direct threads where one of the coach's clients waits for an answer."
  def count_awaiting_reply(_coach_id, []), do: 0

  def count_awaiting_reply(coach_id, client_ids),
    do: MessageStore.count_awaiting_reply(coach_id, client_ids)

  @doc "Adds a member of staff to a thread (a message from the box is the gym's thread)."
  def add_participant(thread_id, user_id), do: ThreadStore.add_participant(thread_id, user_id)

  def message_topics, do: Palee.Messaging.Message.topics()

  @doc "Boxes where the person in `context` (a user scope) has their own conversation."
  def list_box_conversation_organization_ids(%{user_id: _} = context),
    do:
      with_tenant_context(context, fn ->
        Palee.Messaging.ThreadStore.list_box_conversation_organization_ids()
      end)

  def find_context_thread(context_type, context_id),
    do: Palee.Messaging.ThreadStore.find_context_thread(context_type, context_id)

  def count_unread_threads(user_id),
    do: Palee.Messaging.ThreadStore.count_unread_threads(user_id)

  @doc "Direct threads whose latest message is from a client (ADR-098)."
  def list_awaiting_staff_reply(context, staff_ids),
    do: MessageStore.list_awaiting_staff_reply(context, staff_ids)

  # ADR-117 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: Palee.Messaging.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
