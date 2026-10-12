defmodule MilosTraining.Messaging do
  alias MilosTraining.Messaging.Application.{
    GetOrCreateThread,
    SendMessage,
    ListMessages,
    ListThreads,
    MarkRead,
    GetThread
  }

  alias MilosTraining.Messaging.ThreadStore

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: ThreadStore.with_tenant_context(context, fun)

  # ADR-105 staff response latency facts.
  defdelegate first_staff_response_facts(messages, new_message, staff_ids),
    to: MilosTraining.Messaging.Domain.ResponseLatency,
    as: :first_staff_response

  defdelegate get_or_create_thread(params), to: GetOrCreateThread, as: :call
  defdelegate send_message(params), to: SendMessage, as: :call
  defdelegate send_message(params, delivery), to: SendMessage, as: :call
  defdelegate list_messages(thread_id, params), to: ListMessages, as: :call
  defdelegate list_threads_for_user(user_id, context_type \\ nil), to: ListThreads, as: :call
  defdelegate mark_read(thread_id, user_id, message_id), to: MarkRead, as: :call
  defdelegate get_thread(thread_id, user_id), to: GetThread, as: :call
  def get_message(message_id), do: MilosTraining.Messaging.MessageStore.get_message(message_id)

  def list_recent_coaching_notes(user_id, limit \\ 5)
      when is_integer(limit) and limit in 1..50,
      do: MilosTraining.Messaging.MessageStore.list_recent_coaching_notes(user_id, limit)

  def list_recent_coaching_notes_for_organization(user_id, limit \\ 5)
      when is_integer(limit) and limit in 1..50,
      do:
        MilosTraining.Messaging.MessageStore.list_recent_coaching_notes_for_organization(
          user_id,
          limit
        )

  def count_unread_threads(user_id),
    do: MilosTraining.Messaging.ThreadStore.count_unread_threads(user_id)

  # ADR-099 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: MilosTraining.Messaging.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
