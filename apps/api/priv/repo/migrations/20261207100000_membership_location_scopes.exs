defmodule Palee.Repo.Migrations.MembershipLocationScopes do
  @moduledoc """
  ADR-186: staff work at some branches of a business, not necessarily all.

  - `organization_memberships.all_locations` is the explicit «Όλα τα
    καταστήματα» flag. It defaults to true, so every existing membership keeps
    working everywhere.
  - `membership_location_scopes` lists the branches of a membership whose flag
    is off, one row per branch. Composite foreign keys keep both the membership
    and the location inside the same organization; deleting either removes the
    row. Archived locations stay in the table and drop out of the scope when it
    is read, so un-archiving a branch gives it back to its staff.
  - A unique index on `organization_memberships (id, organization_id)` makes
    the composite foreign key possible.
  """

  use Ecto.Migration

  def up do
    alter table(:organization_memberships) do
      add :all_locations, :boolean, null: false, default: true
    end

    create unique_index(:organization_memberships, [:id, :organization_id],
             name: :organization_memberships_id_organization_index
           )

    create table(:membership_location_scopes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_id, :binary_id, null: false
      add :location_id, :binary_id, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE membership_location_scopes
    ADD CONSTRAINT membership_location_scopes_membership_id_fkey
    FOREIGN KEY (membership_id, organization_id)
    REFERENCES organization_memberships (id, organization_id) ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE membership_location_scopes
    ADD CONSTRAINT membership_location_scopes_location_id_fkey
    FOREIGN KEY (location_id, organization_id)
    REFERENCES facility_locations (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:membership_location_scopes, [:membership_id, :location_id])
    create index(:membership_location_scopes, [:location_id])
    create index(:membership_location_scopes, [:organization_id])

    execute("""
    CREATE TRIGGER membership_location_scopes_apply_tenant_context
    BEFORE INSERT OR UPDATE ON membership_location_scopes
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY membership_location_scopes_tenant_policy ON membership_location_scopes
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE membership_location_scopes ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE membership_location_scopes FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:membership_location_scopes)
    drop index(:organization_memberships, [:id, :organization_id],
           name: :organization_memberships_id_organization_index
         )

    alter table(:organization_memberships) do
      remove :all_locations
    end
  end
end
