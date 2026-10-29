defmodule Palee.Repo.Migrations.CreateSetupRecipeApplications do
  @moduledoc """
  ADR-255: the record of applied setup recipes (CP-H2): which recipe and
  version, when, by whom, and the changes it made. Insert-only.
  """

  use Ecto.Migration

  def up do
    create table(:setup_recipe_applications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :recipe_key, :string, size: 60, null: false
      add :recipe_version, :integer, null: false
      add :applied_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :applied_at, :utc_datetime_usec, null: false
      add :changes, {:array, :map}, null: false, default: []
      add :manual, {:array, :map}, null: false, default: []
      add :change_count, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:setup_recipe_applications, [:organization_id, :applied_at])

    create constraint(:setup_recipe_applications, :setup_recipe_applications_check,
             check: "recipe_version > 0 AND change_count >= 0"
           )

    execute("""
    CREATE TRIGGER setup_recipe_applications_apply_tenant_context
    BEFORE INSERT OR UPDATE ON setup_recipe_applications
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY setup_recipe_applications_tenant_policy ON setup_recipe_applications
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE setup_recipe_applications ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE setup_recipe_applications FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:setup_recipe_applications)
  end
end
