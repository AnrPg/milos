defmodule Palee.Messaging.Ports.ThreadStore do
  alias Palee.Messaging.Thread

  @callback get_thread(Ecto.UUID.t()) :: Thread.t() | nil
  @callback get_thread_with_participants(Ecto.UUID.t()) :: Thread.t() | nil
  @callback find_direct_thread(Ecto.UUID.t(), Ecto.UUID.t()) :: Thread.t() | nil
  @callback find_context_thread(atom(), Ecto.UUID.t()) :: Thread.t() | nil
  @callback list_threads_for_user(Ecto.UUID.t(), atom() | nil) :: [Thread.t()]
  @callback create_thread(map()) :: {:ok, Thread.t()} | {:error, Ecto.Changeset.t()}
  @callback get_or_create_thread(map(), [Ecto.UUID.t()]) ::
              {:ok, Thread.t()} | {:error, Ecto.Changeset.t() | term()}
  @callback add_participant(Ecto.UUID.t(), Ecto.UUID.t()) ::
              {:ok, Palee.Messaging.Participant.t()} | {:error, Ecto.Changeset.t()}
  @callback mark_read(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
              {:ok, Ecto.UUID.t()} | {:error, :not_found | :invalid_message}
  @callback count_unread_threads(Ecto.UUID.t()) :: non_neg_integer()
  @doc "Boxes where the signed-in person (the session's user) has their own conversation."
  @callback list_box_conversation_organization_ids() :: [Ecto.UUID.t()]

  # ADR-282: the box's shared inbox.
  @callback add_participant(Ecto.UUID.t(), Ecto.UUID.t(), atom() | nil) ::
              {:ok, Palee.Messaging.Participant.t()} | {:error, Ecto.Changeset.t()}
  @doc "Gives `user_id` a row (read marker) in every box thread of the tenant they lack one in."
  @callback join_box_threads(Ecto.UUID.t()) :: non_neg_integer()
  @callback box_blocked?(Ecto.UUID.t()) :: boolean()
  @callback list_box_blocked_user_ids([Ecto.UUID.t()]) :: [Ecto.UUID.t()]
  @callback block_box_sender(Ecto.UUID.t(), Ecto.UUID.t()) ::
              {:ok, Palee.Messaging.BoxBlock.t()} | {:error, Ecto.Changeset.t()}
  @callback unblock_box_sender(Ecto.UUID.t()) :: :ok
end
