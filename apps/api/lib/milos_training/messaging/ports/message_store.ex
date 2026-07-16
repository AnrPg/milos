defmodule MilosTraining.Messaging.Ports.MessageStore do
  alias MilosTraining.Messaging.Message

  @callback create_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  @callback create_message_with_delivery(map(), map()) ::
              {:ok, Message.t()} | {:error, Ecto.Changeset.t() | term()}
  @callback list_messages(Ecto.UUID.t(), map()) :: [Message.t()]
  @callback get_message(Ecto.UUID.t()) :: Message.t() | nil
  @callback list_recent_coaching_notes(Ecto.UUID.t(), pos_integer()) :: [Message.t()]
end
