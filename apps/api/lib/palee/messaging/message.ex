defmodule Palee.Messaging.Message do
  use Ecto.Schema
  import Ecto.Changeset

  # ADR-140 §6: chat; a coaching message (a coach with an active coaching
  # relationship, metered); a message from the box (operational staff, about
  # an optional topic); system. A person writing to the box picks a topic
  # too; `training` brings in their coach (ADR-282).
  @message_types [:chat, :coaching_message, :box_message, :system]
  @topics ~w(booking payment membership facility training)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messaging_messages" do
    field :organization_id, :binary_id
    belongs_to :thread, Palee.Messaging.Thread
    field :sender_id, :binary_id
    field :body, :string
    field :message_type, Ecto.Enum, values: @message_types, default: :chat
    field :client_operation_id, Ecto.UUID
    field :sequence_number, :integer, read_after_writes: true
    # The journal entry the message is about (Ζητάω απάντηση, ADR-139 §7).
    field :subject_kind, :string
    field :subject_id, :binary_id
    # What a message from the box is about.
    field :topic, :string

    timestamps(updated_at: false)
  end

  @type t :: %__MODULE__{}

  def message_types, do: @message_types
  def topics, do: @topics

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
      :subject_id,
      :topic
    ])
    |> validate_required([:thread_id, :sender_id, :body])
    |> validate_length(:body, min: 1, max: 5000)
    |> validate_topic()
    |> check_constraint(:subject_kind, name: :messaging_messages_subject_check)
    |> check_constraint(:topic, name: :messaging_messages_topic_check)
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:sender_id)
    |> unique_constraint(:client_operation_id,
      name: :messaging_messages_sender_client_operation_id_index
    )
  end

  defp validate_topic(changeset) do
    case get_field(changeset, :topic) do
      nil ->
        changeset

      _topic ->
        changeset
        |> validate_inclusion(:topic, @topics)
        |> then(fn changeset ->
          if get_field(changeset, :message_type) in [:box_message, :chat],
            do: changeset,
            else: add_error(changeset, :topic, "is only for messages to or from the box")
        end)
    end
  end
end
