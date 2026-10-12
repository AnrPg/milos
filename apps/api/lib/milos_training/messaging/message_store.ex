defmodule MilosTraining.Messaging.MessageStore do
  @behaviour MilosTraining.Messaging.Ports.MessageStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

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
  def list_recent_coaching_notes(user_id, limit),
    do: impl().list_recent_coaching_notes(user_id, limit)

  @impl true
  def list_recent_coaching_notes_for_organization(user_id, limit),
    do: impl().list_recent_coaching_notes_for_organization(user_id, limit)

  @impl true
  def list_awaiting_staff_reply(staff_ids), do: impl().list_awaiting_staff_reply(staff_ids)

  def list_awaiting_staff_reply(context, staff_ids),
    do: RepoContext.run(context, fn -> list_awaiting_staff_reply(staff_ids) end)

  defp impl do
    Application.fetch_env!(:milos_training, :messaging_message_store)
  end
end
