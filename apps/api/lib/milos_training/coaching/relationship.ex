defmodule MilosTraining.Coaching.Relationship do
  @moduledoc "A coach coaching a client in one gym (ADR-100)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @origins ~w(assigned self_assigned invited)

  schema "coaching_relationships" do
    field :organization_id, :binary_id, read_after_writes: true
    field :coach_user_id, :binary_id
    field :client_user_id, :binary_id
    field :origin, :string
    field :started_by_id, :binary_id
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :ended_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def start_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :coach_user_id,
      :client_user_id,
      :origin,
      :started_by_id,
      :started_at
    ])
    |> validate_required([:coach_user_id, :client_user_id, :origin, :started_at])
    |> validate_inclusion(:origin, @origins)
    |> unique_constraint([:organization_id, :coach_user_id, :client_user_id],
      name: :coaching_relationships_active_index,
      message: "already coaches this client"
    )
    |> check_constraint(:client_user_id, name: :coaching_relationships_distinct_people)
  end

  def end_changeset(relationship, ended_by_id, at),
    do: change(relationship, ended_at: at, ended_by_id: ended_by_id)
end
