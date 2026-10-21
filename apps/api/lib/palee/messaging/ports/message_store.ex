defmodule Palee.Messaging.Ports.MessageStore do
  alias Palee.Messaging.Message

  @callback create_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  @callback create_message_with_delivery(map(), map()) ::
              {:ok, Message.t()} | {:error, Ecto.Changeset.t() | term()}
  @callback list_messages(Ecto.UUID.t(), map()) :: [Message.t()]
  @callback get_message(Ecto.UUID.t()) :: Message.t() | nil
  @callback list_recent_coaching_messages(Ecto.UUID.t(), pos_integer()) :: [Message.t()]
  @callback list_awaiting_staff_reply([Ecto.UUID.t()]) :: [map()]
  @callback count_sent(Ecto.UUID.t(), atom(), NaiveDateTime.t()) :: non_neg_integer()
  @callback count_awaiting_reply(Ecto.UUID.t(), [Ecto.UUID.t()]) :: non_neg_integer()
  @callback list_recent_coaching_messages_for_organization(Ecto.UUID.t(), pos_integer()) :: [
              Message.t()
            ]
end
