defmodule MilosTraining.Messaging.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @message_types [:chat, :coaching_note, :system]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messaging_messages" do
    belongs_to :thread, MilosTraining.Messaging.Thread
    field :sender_id, :binary_id
    field :body, :string
    field :message_type, Ecto.Enum, values: @message_types, default: :chat
    field :sequence_number, :integer, read_after_writes: true

    timestamps(updated_at: false)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:thread_id, :sender_id, :body, :message_type])
    |> validate_required([:thread_id, :sender_id, :body])
    |> validate_length(:body, min: 1, max: 5000)
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:sender_id)
  end
end
