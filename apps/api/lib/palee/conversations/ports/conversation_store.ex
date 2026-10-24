defmodule Palee.Conversations.Ports.ConversationStore do
  @moduledoc """
  Persistence port for person conversations (ADR-193 §3). Account-scoped:
  every call runs in the acting person's session, and row security lets
  only the pair read or write a conversation and its messages.
  """

  @type context :: map()
  @type id :: binary()
  @type cursor :: {DateTime.t(), id()} | nil

  @callback get(context(), id()) :: map() | nil
  @callback get_between(context(), id(), id()) :: map() | nil
  @doc "Creates the pair's conversation, or answers the one that already exists."
  @callback insert_or_get(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback update(context(), map(), map()) :: {:ok, map()} | {:error, term()}
  @doc "Inserts a message and applies `changes` to its conversation in one transaction."
  @callback append_message(context(), map(), map(), map()) ::
              {:ok, map(), map()} | {:error, term()}
  @callback get_message_by_operation(context(), id(), id()) :: map() | nil
  @doc "The person's conversations in one folder, latest first, as a page."
  @callback list_for(context(), id(), String.t(), cursor(), pos_integer()) :: [map()]
  @callback last_messages(context(), [id()]) :: %{id() => map()}
  @callback list_messages(context(), id(), cursor(), pos_integer()) :: [map()]
  @doc "How many listed conversations hold unread messages, per folder."
  @callback unread_counts(context(), id()) :: %{String.t() => non_neg_integer()}
end
