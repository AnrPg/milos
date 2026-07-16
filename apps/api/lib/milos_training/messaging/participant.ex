defmodule MilosTraining.Messaging.Participant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messaging_participants" do
    belongs_to :thread, MilosTraining.Messaging.Thread
    field :user_id, :binary_id
    field :last_read_message_id, :binary_id

    timestamps(updated_at: false)
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:thread_id, :user_id, :last_read_message_id])
    |> validate_required([:thread_id, :user_id])
    |> unique_constraint([:thread_id, :user_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:last_read_message_id)
  end
end
