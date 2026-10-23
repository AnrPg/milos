defmodule Palee.Organizations.MembershipLocationScope do
  @moduledoc "One branch a branch-scoped staff membership works at (ADR-186)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "membership_location_scopes" do
    field :organization_id, :binary_id
    field :membership_id, :binary_id
    field :location_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(scope \\ %__MODULE__{}, params) do
    scope
    |> cast(params, [:organization_id, :membership_id, :location_id])
    |> validate_required([:organization_id, :membership_id, :location_id])
    |> unique_constraint([:membership_id, :location_id])
    |> foreign_key_constraint(:membership_id,
      name: :membership_location_scopes_membership_id_fkey
    )
    |> foreign_key_constraint(:location_id, name: :membership_location_scopes_location_id_fkey)
  end
end
