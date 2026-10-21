defmodule Palee.Repo.Migrations.CreateFinanceRefundReceipts do
  use Ecto.Migration

  # ADR-126 / TD-022: immutable refund receipts attached to the append-only
  # `finance_payment_reversals` facts (ADR-019), numbered from a per-tenant
  # counter row that is locked in the issuing transaction so the sequence has
  # no gaps. Additive only: no existing column is touched.
  #
  # Both tables mirror the sibling finance tables (ADR-091): `organization_id`
  # stamped by `palee_apply_tenant_context()`, a bare-equality tenant policy,
  # and ENABLE + FORCE row level security.
  @tables ~w(finance_document_counters finance_refund_receipts)

  def up do
    create table(:finance_document_counters, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :document_type, :string, null: false
      add :last_value, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:finance_document_counters, [:organization_id, :document_type],
             name: :finance_document_counters_organization_type_index
           )

    create constraint(:finance_document_counters, :finance_document_counters_type_check,
             check: "document_type IN ('refund_receipt')"
           )

    create constraint(:finance_document_counters, :finance_document_counters_value_check,
             check: "last_value >= 0"
           )

    create table(:finance_refund_receipts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :finance_payment_reversal_id,
          references(:finance_payment_reversals, type: :binary_id, on_delete: :delete_all),
          null: false

      add :membership_payment_id,
          references(:membership_payments, type: :binary_id, on_delete: :delete_all),
          null: false

      add :finance_invoice_id,
          references(:finance_invoices, type: :binary_id, on_delete: :nilify_all)

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :sequence, :bigint, null: false
      add :receipt_number, :string, null: false
      add :reversal_type, :string, null: false
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false
      add :reason, :text
      add :issued_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reversal_occurred_at, :utc_datetime_usec, null: false
      add :issued_at, :utc_datetime_usec, null: false
      add :schema_version, :integer, null: false, default: 1
      add :snapshot, :map, null: false
      add :snapshot_sha256, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:finance_refund_receipts, [:organization_id, :sequence],
             name: :finance_refund_receipts_organization_sequence_index
           )

    create unique_index(:finance_refund_receipts, [:organization_id, :receipt_number],
             name: :finance_refund_receipts_organization_number_index
           )

    create unique_index(:finance_refund_receipts, [:finance_payment_reversal_id],
             name: :finance_refund_receipts_reversal_index
           )

    create index(:finance_refund_receipts, [:organization_id, :issued_at])
    create index(:finance_refund_receipts, [:user_id, :issued_at])
    create index(:finance_refund_receipts, [:membership_payment_id])
    create index(:finance_refund_receipts, [:finance_invoice_id])

    create constraint(:finance_refund_receipts, :finance_refund_receipts_amount_check,
             check: "amount_cents > 0"
           )

    create constraint(:finance_refund_receipts, :finance_refund_receipts_sequence_check,
             check: "sequence > 0"
           )

    # Receipts are immutable. Only the nullable links that a referenced row's
    # ON DELETE SET NULL may clear (and the tenant trigger's no-op re-stamp of
    # organization_id) are allowed to change.
    execute("""
    CREATE OR REPLACE FUNCTION palee_finance_refund_receipts_immutable()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
        OR NEW.finance_payment_reversal_id IS DISTINCT FROM OLD.finance_payment_reversal_id
        OR NEW.membership_payment_id IS DISTINCT FROM OLD.membership_payment_id
        OR NEW.membership_id IS DISTINCT FROM OLD.membership_id
        OR NEW.user_id IS DISTINCT FROM OLD.user_id
        OR NEW.sequence IS DISTINCT FROM OLD.sequence
        OR NEW.receipt_number IS DISTINCT FROM OLD.receipt_number
        OR NEW.reversal_type IS DISTINCT FROM OLD.reversal_type
        OR NEW.amount_cents IS DISTINCT FROM OLD.amount_cents
        OR NEW.currency IS DISTINCT FROM OLD.currency
        OR NEW.reason IS DISTINCT FROM OLD.reason
        OR NEW.reversal_occurred_at IS DISTINCT FROM OLD.reversal_occurred_at
        OR NEW.issued_at IS DISTINCT FROM OLD.issued_at
        OR NEW.schema_version IS DISTINCT FROM OLD.schema_version
        OR NEW.snapshot IS DISTINCT FROM OLD.snapshot
        OR NEW.snapshot_sha256 IS DISTINCT FROM OLD.snapshot_sha256
        OR (NEW.finance_invoice_id IS DISTINCT FROM OLD.finance_invoice_id
            AND NEW.finance_invoice_id IS NOT NULL)
        OR (NEW.issued_by_id IS DISTINCT FROM OLD.issued_by_id AND NEW.issued_by_id IS NOT NULL)
      THEN
        RAISE EXCEPTION 'finance_refund_receipts rows are immutable'
          USING ERRCODE = '55000';
      END IF;

      RETURN NEW;
    END
    $$
    """)

    execute("""
    CREATE TRIGGER finance_refund_receipts_immutable
    BEFORE UPDATE ON finance_refund_receipts
    FOR EACH ROW EXECUTE FUNCTION palee_finance_refund_receipts_immutable()
    """)

    Enum.each(@tables, &enforce_tenant_boundary/1)
  end

  def down do
    Enum.each(@tables, &drop_tenant_boundary/1)

    execute("DROP TRIGGER IF EXISTS finance_refund_receipts_immutable ON finance_refund_receipts")
    execute("DROP FUNCTION IF EXISTS palee_finance_refund_receipts_immutable()")

    drop table(:finance_refund_receipts)
    drop table(:finance_document_counters)
  end

  defp enforce_tenant_boundary(table) do
    execute("""
    CREATE TRIGGER #{table}_apply_tenant_context
    BEFORE INSERT OR UPDATE ON #{table}
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY #{table}_tenant_policy ON #{table}
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
  end

  defp drop_tenant_boundary(table) do
    execute("ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY")
    execute("DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}")
    execute("DROP TRIGGER IF EXISTS #{table}_apply_tenant_context ON #{table}")
  end
end
