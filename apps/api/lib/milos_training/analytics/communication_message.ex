defmodule MilosTraining.Analytics.CommunicationMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "communication_messages" do
    field :thread_id, :binary_id
    field :sender_id, :binary_id
    field :recipient_id, :binary_id
    field :sender_role_snapshot, :string
    field :recipient_role_snapshot, :string
    field :direction, :string
    field :channel, :string, default: "in_app"
    field :body, :string
    field :sentiment_tag, :string
    field :sent_at, :utc_datetime_usec
    field :params, :map, default: %{}

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(message \\ %__MODULE__{}, params) do
    message
    |> cast(params, [
      :thread_id,
      :sender_id,
      :recipient_id,
      :sender_role_snapshot,
      :recipient_role_snapshot,
      :direction,
      :channel,
      :body,
      :sentiment_tag,
      :sent_at,
      :params
    ])
    |> validate_required([
      :thread_id,
      :sender_id,
      :sender_role_snapshot,
      :direction,
      :channel,
      :body,
      :sent_at
    ])
    |> validate_inclusion(:direction, [
      "user_to_admin",
      "admin_to_user",
      "admin_to_admin",
      "user_to_user"
    ])
    |> validate_inclusion(:channel, ["in_app", "push", "email", "sms", "manual"])
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:sender_id)
    |> foreign_key_constraint(:recipient_id)
  end
end
