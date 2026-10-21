defmodule Palee.Repo.Migrations.AddCorporateInvoicing do
  use Ecto.Migration

  # ADR-098 corporate invoicing: payment terms and automatic invoicing per
  # client, numbered invoices with due dates and reminders, and payments.
  def up do
    alter table(:finance_corporate_clients) do
      add :payment_terms_days, :integer, null: false, default: 14
      add :auto_invoice, :boolean, null: false, default: true
    end

    create constraint(:finance_corporate_clients, :finance_corporate_clients_payment_terms,
             check: "payment_terms_days BETWEEN 0 AND 120"
           )

    alter table(:finance_corporate_invoices) do
      add :invoice_number, :string
      add :due_on, :date
      add :last_reminded_on, :date
      add :reminder_count, :integer, null: false, default: 0
    end

    execute("UPDATE finance_corporate_invoices SET due_on = issued_on + 14 WHERE due_on IS NULL")
    execute("ALTER TABLE finance_corporate_invoices ALTER COLUMN due_on SET NOT NULL")

    create unique_index(:finance_corporate_invoices, [:organization_id, :invoice_number],
             name: :finance_corporate_invoices_number_index,
             where: "invoice_number IS NOT NULL"
           )

    create unique_index(:finance_corporate_invoices, [:id, :organization_id],
             name: :finance_corporate_invoices_id_organization_index
           )

    drop constraint(:finance_corporate_invoices, :finance_corporate_invoices_status)

    create constraint(:finance_corporate_invoices, :finance_corporate_invoices_status,
             check: "status IN ('issued', 'overdue', 'paid', 'void')"
           )

    create table(:finance_corporate_payments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :corporate_invoice_id, :binary_id, null: false
      add :amount_cents, :integer, null: false
      add :payment_method, :string, null: false
      add :paid_on, :date, null: false
      add :reference, :string
      add :notes, :text
      add :recorded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reversed_at, :utc_datetime_usec
      add :reversed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reversal_reason, :text
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE finance_corporate_payments
    ADD CONSTRAINT finance_corporate_payments_invoice_fkey
    FOREIGN KEY (corporate_invoice_id, organization_id)
    REFERENCES finance_corporate_invoices (id, organization_id) ON DELETE CASCADE
    """)

    create index(:finance_corporate_payments, [:corporate_invoice_id])

    create constraint(:finance_corporate_payments, :finance_corporate_payments_amount,
             check: "amount_cents > 0"
           )

    create constraint(:finance_corporate_payments, :finance_corporate_payments_method,
             check: "payment_method IN ('cash', 'bank_transfer', 'card_manual', 'other')"
           )

    execute("""
    CREATE TRIGGER finance_corporate_payments_apply_tenant_context
    BEFORE INSERT OR UPDATE ON finance_corporate_payments
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY finance_corporate_payments_tenant_policy ON finance_corporate_payments
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE finance_corporate_payments ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE finance_corporate_payments FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:finance_corporate_payments)

    drop constraint(:finance_corporate_invoices, :finance_corporate_invoices_status)

    execute("UPDATE finance_corporate_invoices SET status = 'issued' WHERE status = 'overdue'")

    create constraint(:finance_corporate_invoices, :finance_corporate_invoices_status,
             check: "status IN ('issued', 'paid', 'void')"
           )

    drop index(:finance_corporate_invoices, [:id, :organization_id],
           name: :finance_corporate_invoices_id_organization_index
         )

    drop index(:finance_corporate_invoices, [:organization_id, :invoice_number],
           name: :finance_corporate_invoices_number_index
         )

    alter table(:finance_corporate_invoices) do
      remove :invoice_number
      remove :due_on
      remove :last_reminded_on
      remove :reminder_count
    end

    drop constraint(:finance_corporate_clients, :finance_corporate_clients_payment_terms)

    alter table(:finance_corporate_clients) do
      remove :payment_terms_days
      remove :auto_invoice
    end
  end
end
