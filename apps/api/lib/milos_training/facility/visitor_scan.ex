defmodule MilosTraining.Facility.VisitorScan do
  @moduledoc """
  A person who is not a member scanned the door (ADR-155, decision 3); the
  desk lists them as «Επισκέπτης».
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "facility_visitor_scans" do
    field :organization_id, :binary_id
    field :location_id, :binary_id
    field :user_id, :binary_id
    field :scanned_at, :utc_datetime_usec
    field :trial_offered, :boolean, default: false

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(scan \\ %__MODULE__{}, attrs) do
    scan
    |> cast(attrs, [:organization_id, :location_id, :user_id, :scanned_at, :trial_offered])
    |> validate_required([:organization_id, :user_id, :scanned_at])
    |> foreign_key_constraint(:location_id)
    |> foreign_key_constraint(:user_id)
  end
end
