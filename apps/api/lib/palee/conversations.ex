defmodule Palee.Conversations do
  @moduledoc """
  Person-to-person conversations (ADR-193 §3): one per pair of people,
  account-scoped and independent of any gym, with an inbox, message
  requests and declines. The gym's own threads (box, coach, class) stay in
  `Palee.Messaging`.
  """

  alias Palee.Conversations.ConversationStore
  alias Palee.Conversations.Domain.ConversationPolicy

  defdelegate get(context, id), to: ConversationStore
  defdelegate get_between(context, a, b), to: ConversationStore
  defdelegate insert_or_get(context, attrs), to: ConversationStore
  defdelegate update(context, conversation, changes), to: ConversationStore
  defdelegate append_message(context, conversation, attrs, changes), to: ConversationStore
  defdelegate get_message_by_operation(context, author_id, operation_id), to: ConversationStore
  defdelegate list_for(context, user_id, folder, cursor, limit), to: ConversationStore
  defdelegate last_messages(context, ids), to: ConversationStore
  defdelegate list_messages(context, conversation_id, cursor, limit), to: ConversationStore
  defdelegate unread_counts(context, user_id), to: ConversationStore

  defdelegate pair(one, other), to: ConversationPolicy
  defdelegate side(conversation, user_id), to: ConversationPolicy
  defdelegate party?(conversation, user_id), to: ConversationPolicy
  defdelegate other(conversation, user_id), to: ConversationPolicy
  defdelegate folder(conversation, user_id), to: ConversationPolicy
  defdelegate listed?(conversation, user_id), to: ConversationPolicy
  defdelegate listed_folders(), to: ConversationPolicy
  defdelegate unread?(conversation, user_id), to: ConversationPolicy
  defdelegate buddies?(facts), to: ConversationPolicy
  defdelegate inbox?(facts), to: ConversationPolicy
  defdelegate new_folders(starter_id, other_id, facts), to: ConversationPolicy
  defdelegate after_message(conversation, author_id, facts, now), to: ConversationPolicy
  defdelegate accept(conversation, user_id), to: ConversationPolicy
  defdelegate decline(conversation, user_id), to: ConversationPolicy
  defdelegate mark_read(conversation, user_id, now), to: ConversationPolicy
  defdelegate normalize_body(body), to: ConversationPolicy
  defdelegate page_limit(value), to: ConversationPolicy
  defdelegate encode_cursor(at, id), to: ConversationPolicy
  defdelegate decode_cursor(cursor), to: ConversationPolicy
end
