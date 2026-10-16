defmodule MilosTraining.Messaging.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @message_types [:chat, :coaching_note, :system]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messaging_messages" do
    field :organization_id, :binary_id
    belongs_to :thread, MilosTraining.Messaging.Thread
    field :sender_id, :binary_id
    field :body, :string
    field :message_type, Ecto.Enum, values: @message_types, default: :chat
    field :client_operation_id, Ecto.UUID
    field :sequence_number, :integer, read_after_writes: true
    # The journal entry the message is about (Ζητάω απάντηση, ADR-139 §7).
    field :subject_kind, :string
    field :subject_id, :binary_id

    timestamps(updated_at: false)
  end

  @type t :: %__MODULE__{}

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :organization_id,
      :thread_id,
      :sender_id,
      :body,
      :message_type,
      :client_operation_id,
      :subject_kind,
      :subject_id
    ])
    |> validate_required([:thread_id, :sender_id, :body])
    |> validate_length(:body, min: 1, max: 5000)
    |> check_constraint(:subject_kind, name: :messaging_messages_subject_check)
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:sender_id)
    |> unique_constraint(:client_operation_id,
      name: :messaging_messages_sender_client_operation_id_index
    )
  end
end
