defmodule Palee.Conversations.ConversationStore do
  @moduledoc """
  Facade over the configured person conversations adapter (ADR-193 §3).
  Every call runs inside a `RepoContext` session, the acting person's.
  """

  @behaviour Palee.Conversations.Ports.ConversationStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :conversation_store)

  defp scoped(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def get(context, id), do: scoped(context, :get, [id])

  @impl true
  def get_between(context, a, b), do: scoped(context, :get_between, [a, b])

  @impl true
  def insert_or_get(context, attrs), do: scoped(context, :insert_or_get, [attrs])

  @impl true
  def update(context, conversation, changes),
    do: scoped(context, :update, [conversation, changes])

  @impl true
  def append_message(context, conversation, attrs, changes),
    do: scoped(context, :append_message, [conversation, attrs, changes])

  @impl true
  def get_message_by_operation(context, author_id, operation_id),
    do: scoped(context, :get_message_by_operation, [author_id, operation_id])

  @impl true
  def list_for(context, user_id, folder, cursor, limit),
    do: scoped(context, :list_for, [user_id, folder, cursor, limit])

  @impl true
  def last_messages(context, ids), do: scoped(context, :last_messages, [ids])

  @impl true
  def list_messages(context, conversation_id, cursor, limit),
    do: scoped(context, :list_messages, [conversation_id, cursor, limit])

  @impl true
  def unread_counts(context, user_id), do: scoped(context, :unread_counts, [user_id])
end
