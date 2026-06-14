defmodule MilosTraining.Messaging.Ports.MessageStore do
  alias MilosTraining.Messaging.Message

  @callback create_message(map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  @callback list_messages(Ecto.UUID.t(), map()) :: [Message.t()]
  @callback get_message(Ecto.UUID.t()) :: Message.t() | nil
end
