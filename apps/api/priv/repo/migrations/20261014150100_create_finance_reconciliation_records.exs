defmodule Palee.Repo.Migrations.CreateFinanceReconciliationRecords do
  use Ecto.Migration

  # ADR-126 / TD-022: provider-agnostic reconciliation records. Each row is
  # one external statement line (a provider payment or refund) recorded
  # manually by staff and optionally matched to exactly one internal fact - a
  # `membership_payments` row or a `finance_payment_reversals` row. Recording
  # is idempotent on (organization, provider, external_reference). No provider
  # API integration exists; providers attach here without changing the core
  # payment/reversal schema.
  def up do
    create table(:finance_reconciliation_records, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :provider, :string, null: false
      add :external_reference, :string, null: false
      add :external_type, :string, null: false
      add :external_status, :string, null: false, default: "settled"
      add :statement_amount_cents, :integer, null: false
      add :statement_currency, :string, null: false
      add :statement_occurred_on, :date, null: false
      add :statement_description, :text
      add :status, :string, null: false, default: "unmatched"

      add :membership_payment_id,
          references(:membership_payments, type: :binary_id, on_delete: :nilify_all)

      add :finance_payment_reversal_id,
          references(:finance_payment_reversals, type: :binary_id, on_delete: :nilify_all)

      add :discrepancies, {:array, :string}, null: false, default: []
      add :discrepancy_notes, :text
      add :matched_at, :utc_datetime_usec
      add :matched_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :recorded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :finance_reconciliation_records,
             [:organization_id, :provider, :external_reference],
             name: :finance_reconciliation_records_external_index
           )

    create unique_index(
             :finance_reconciliation_records,
             [:organization_id, :membership_payment_id],
             name: :finance_reconciliation_records_payment_index,
             where: "membership_payment_id IS NOT NULL"
           )

    create unique_index(
             :finance_reconciliation_records,
             [:organization_id, :finance_payment_reversal_id],
             name: :finance_reconciliation_records_reversal_index,
             where: "finance_payment_reversal_id IS NOT NULL"
           )

    create index(:finance_reconciliation_records, [:organization_id, :status])
    create index(:finance_reconciliation_records, [:organization_id, :statement_occurred_on])

    create constraint(:finance_reconciliation_records, :finance_reconciliation_type_check,
             check: "external_type IN ('payment', 'refund')"
           )

    create constraint(
             :finance_reconciliation_records,
             :finance_reconciliation_external_status_check,
             check: "external_status IN ('settled', 'pending', 'failed')"
           )

    create constraint(:finance_reconciliation_records, :finance_reconciliation_status_check,
             check: "status IN ('unmatched', 'matched', 'mismatched')"
           )

    create constraint(:finance_reconciliation_records, :finance_reconciliation_amount_check,
             check: "statement_amount_cents > 0"
           )

    create constraint(
             :finance_reconciliation_records,
             :finance_reconciliation_single_target_check,
             check: "membership_payment_id IS NULL OR finance_payment_reversal_id IS NULL"
           )

    execute("""
    CREATE TRIGGER finance_reconciliation_records_apply_tenant_context
    BEFORE INSERT OR UPDATE ON finance_reconciliation_records
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY finance_reconciliation_records_tenant_policy ON finance_reconciliation_records
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE finance_reconciliation_records ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE finance_reconciliation_records FORCE ROW LEVEL SECURITY")
  end

  def down do
    execute("ALTER TABLE finance_reconciliation_records NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE finance_reconciliation_records DISABLE ROW LEVEL SECURITY")

    execute(
      "DROP POLICY IF EXISTS finance_reconciliation_records_tenant_policy ON finance_reconciliation_records"
    )

    execute(
      "DROP TRIGGER IF EXISTS finance_reconciliation_records_apply_tenant_context ON finance_reconciliation_records"
    )

    drop table(:finance_reconciliation_records)
  end
end
