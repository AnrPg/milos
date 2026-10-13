defmodule MilosTraining.Coaching.Note do
  @moduledoc "A coach's private note about a client (ADR-101)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "coaching_notes" do
    field :organization_id, :binary_id, read_after_writes: true
    field :coach_user_id, :binary_id
    field :client_user_id, :binary_id
    field :body, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(note \\ %__MODULE__{}, attrs) do
    note
    |> cast(attrs, [:organization_id, :coach_user_id, :client_user_id, :body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:coach_user_id, :client_user_id, :body])
    |> validate_length(:body, min: 1, max: 5_000)
  end
end
