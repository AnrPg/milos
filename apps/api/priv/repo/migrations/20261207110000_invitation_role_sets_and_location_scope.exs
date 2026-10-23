defmodule Palee.Repo.Migrations.InvitationRoleSetsAndLocationScope do
  @moduledoc """
  ADR-186: one invitation link carries a role set and a branch scope
  («Coach @ Κηφισιά + Μαρούσι»).

  - `roles` is the role set; `role` stays as its primary role, so existing
    links, the role check constraint and API clients that send or read one
    role keep working. An empty `roles` means `[role]`.
  - `all_locations` / `location_ids` are the branch scope the redeemed
    membership gets. An invitation is short-lived and single-use, so the ids
    are an array checked when it is issued; branches that are gone by the time
    it is redeemed are dropped then.
  """

  use Ecto.Migration

  @roles ~w(owner admin coach front_desk accountant janitor member athlete)

  def up do
    alter table(:registration_invitations) do
      add :roles, {:array, :string}, null: false, default: []
      add :all_locations, :boolean, null: false, default: true
      add :location_ids, {:array, :binary_id}, null: false, default: []
    end

    create constraint(:registration_invitations, :registration_invitations_roles_check,
             check: "roles <@ ARRAY[#{Enum.map_join(@roles, ", ", &"'#{&1}'")}]::varchar[]"
           )

    create constraint(:registration_invitations, :registration_invitations_location_scope_check,
             check: "all_locations OR cardinality(location_ids) BETWEEN 1 AND 200"
           )
  end

  def down do
    drop constraint(:registration_invitations, :registration_invitations_location_scope_check)
    drop constraint(:registration_invitations, :registration_invitations_roles_check)

    alter table(:registration_invitations) do
      remove :location_ids
      remove :all_locations
      remove :roles
    end
  end
end
