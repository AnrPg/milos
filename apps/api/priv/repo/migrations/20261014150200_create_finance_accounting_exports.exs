defmodule Palee.Repo.Migrations.CreateFinanceAccountingExports do
  use Ecto.Migration

  # ADR-126 / TD-022: audit record of every accounting export run - who asked,
  # when, for which date range, how it ran, and the stored artifact's object
  # key, size and SHA-256. The artifact itself lives in the tenant object
  # store under `organizations/<id>/finance/accounting-exports/...` so the
  # ADR-117 inventory and purge see it.
  def up do
    create table(:finance_accounting_exports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :requested_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :range_start, :date, null: false
      add :range_end, :date, null: false
      add :status, :string, null: false, default: "queued"
      add :execution_mode, :string, null: false
      add :schema_version, :integer, null: false, default: 1
      add :object_key, :string
      add :byte_size, :bigint
      add :sha256, :string
      add :row_counts, :map, null: false, default: %{}
      add :files, {:array, :map}, null: false, default: []
      add :error_reason, :string
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:finance_accounting_exports, [:organization_id, :inserted_at])

    create constraint(:finance_accounting_exports, :finance_accounting_exports_status_check,
             check: "status IN ('queued', 'running', 'completed', 'failed')"
           )

    create constraint(:finance_accounting_exports, :finance_accounting_exports_mode_check,
             check: "execution_mode IN ('inline', 'background')"
           )

    create constraint(:finance_accounting_exports, :finance_accounting_exports_range_check,
             check: "range_end >= range_start"
           )

    execute("""
    CREATE TRIGGER finance_accounting_exports_apply_tenant_context
    BEFORE INSERT OR UPDATE ON finance_accounting_exports
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY finance_accounting_exports_tenant_policy ON finance_accounting_exports
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE finance_accounting_exports ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE finance_accounting_exports FORCE ROW LEVEL SECURITY")
  end

  def down do
    execute("ALTER TABLE finance_accounting_exports NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE finance_accounting_exports DISABLE ROW LEVEL SECURITY")

    execute(
      "DROP POLICY IF EXISTS finance_accounting_exports_tenant_policy ON finance_accounting_exports"
    )

    execute(
      "DROP TRIGGER IF EXISTS finance_accounting_exports_apply_tenant_context ON finance_accounting_exports"
    )

    drop table(:finance_accounting_exports)
  end
end
