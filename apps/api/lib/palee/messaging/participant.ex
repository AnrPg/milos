defmodule Palee.Messaging.Participant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messaging_participants" do
    field :organization_id, :binary_id
    belongs_to :thread, Palee.Messaging.Thread
    field :user_id, :binary_id
    field :last_read_message_id, :binary_id
    # ADR-282: why someone is in a box thread (nil in the other threads).
    field :joined_as, Ecto.Enum, values: [:member, :staff, :coach]

    timestamps(updated_at: false)
  end

  @type t :: %__MODULE__{}

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:organization_id, :thread_id, :user_id, :last_read_message_id, :joined_as])
    |> validate_required([:thread_id, :user_id])
    |> unique_constraint([:thread_id, :user_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:last_read_message_id)
  end
end
