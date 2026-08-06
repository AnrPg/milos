defmodule MilosTraining.Organizations.OrganizationProvisioningEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "organization_provisioning_events" do
    field :organization_id, :binary_id
    field :vendor_user_id, :binary_id
    field :event, :string
    field :metadata, :map, default: %{}
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(event \\ %__MODULE__{}, params) do
    event
    |> cast(params, [:organization_id, :vendor_user_id, :event, :metadata])
    |> validate_required([:organization_id, :vendor_user_id, :event, :metadata])
    |> validate_length(:event, min: 2, max: 80)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:vendor_user_id)
  end
end
