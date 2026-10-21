defmodule Palee.Organizations.OrganizationMembership do
  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Organizations.Domain.MembershipPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_memberships" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    # Primary role: the most privileged of `roles`, kept in sync (ADR-099).
    field :role, Ecto.Enum, values: MembershipPolicy.roles()
    field :roles, {:array, Ecto.Enum}, values: MembershipPolicy.roles(), default: []
    field :coach_scope, Ecto.Enum, values: [:own, :all], default: :own
    field :notes_visible_to_admins, :boolean, default: true
    field :status, Ecto.Enum, values: MembershipPolicy.statuses(), default: :active
    field :joined_at, :utc_datetime_usec
    field :invited_by_user_id, :binary_id
    # The location this person's gym opens on (Phase 2); nil = no default.
    field :home_location_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def changeset(membership \\ %__MODULE__{}, params) do
    membership
    |> cast(params, [
      :organization_id,
      :user_id,
      :role,
      :roles,
      :status,
      :joined_at,
      :invited_by_user_id,
      :coach_scope,
      :notes_visible_to_admins,
      :home_location_id
    ])
    |> sync_roles()
    |> validate_required([:organization_id, :user_id, :role, :status])
    |> validate_length(:roles, min: 1)
    |> unique_constraint([:organization_id, :user_id])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:invited_by_user_id)
    |> foreign_key_constraint(:home_location_id,
      name: :organization_memberships_home_location_fkey
    )
  end

  # `roles` is the role set; `role` mirrors its primary role. A caller that
  # sets only `role` (legacy single-role writes) replaces the set with it.
  defp sync_roles(changeset) do
    case {fetch_change(changeset, :roles), fetch_change(changeset, :role)} do
      {{:ok, roles}, _role} ->
        roles = Enum.filter(MembershipPolicy.roles(), &(&1 in roles))

        changeset
        |> put_change(:roles, roles)
        |> put_change(:role, MembershipPolicy.primary_role(roles))

      {:error, {:ok, role}} when not is_nil(role) ->
        put_change(changeset, :roles, [role])

      _unchanged ->
        if get_field(changeset, :roles) in [nil, []] and get_field(changeset, :role),
          do: put_change(changeset, :roles, [get_field(changeset, :role)]),
          else: changeset
    end
  end
end
