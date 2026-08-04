defmodule MilosTraining.Organizations.OrganizationMembership do
  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Organizations.Domain.MembershipPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_memberships" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :role, Ecto.Enum, values: MembershipPolicy.roles()
    field :status, Ecto.Enum, values: MembershipPolicy.statuses(), default: :active
    field :joined_at, :utc_datetime_usec
    field :invited_by_user_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership \\ %__MODULE__{}, params) do
    membership
    |> cast(params, [
      :organization_id,
      :user_id,
      :role,
      :status,
      :joined_at,
      :invited_by_user_id
    ])
    |> validate_required([:organization_id, :user_id, :role, :status])
    |> unique_constraint([:organization_id, :user_id])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:invited_by_user_id)
  end
end
