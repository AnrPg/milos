defmodule MilosTraining.Repo.Migrations.CreateFinanceInvoicesAndEntitlements do
  use Ecto.Migration

  def change do
    create table(:finance_invoices, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :membership_package_subscription_id,
          references(:membership_package_subscriptions, type: :binary_id, on_delete: :nilify_all)

      add :invoice_number, :string, null: false
      add :invoice_type, :string, null: false, default: "manual"
      add :status, :string, null: false, default: "draft"
      add :issue_date, :date
      add :due_date, :date
      add :service_period_start, :date
      add :service_period_end, :date
      add :subtotal_cents, :integer, null: false, default: 0
      add :discount_cents, :integer, null: false, default: 0
      add :total_cents, :integer, null: false, default: 0
      add :currency, :string, null: false, default: "EUR"
      add :notes, :text
      add :voided_at, :utc_datetime_usec
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:finance_invoices, [:invoice_number])
    create index(:finance_invoices, [:membership_id, :status])
    create index(:finance_invoices, [:user_id, :status])
    create index(:finance_invoices, [:due_date, :status])
    create index(:finance_invoices, [:membership_package_subscription_id])

    create constraint(:finance_invoices, :finance_invoices_type_check,
             check: "invoice_type IN ('manual', 'renewal', 'adjustment')"
           )

    create constraint(:finance_invoices, :finance_invoices_status_check,
             check: "status IN ('draft', 'issued', 'partially_paid', 'paid', 'overdue', 'void')"
           )

    create constraint(:finance_invoices, :finance_invoices_amounts_check,
             check: "subtotal_cents >= 0 AND discount_cents >= 0 AND total_cents >= 0"
           )

    create table(:finance_invoice_lines, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :finance_invoice_id,
          references(:finance_invoices, type: :binary_id, on_delete: :delete_all),
          null: false

      add :membership_package_subscription_id,
          references(:membership_package_subscriptions, type: :binary_id, on_delete: :nilify_all)

      add :line_type, :string, null: false, default: "membership_package"
      add :description, :string, null: false
      add :quantity, :integer, null: false, default: 1
      add :unit_amount_cents, :integer, null: false, default: 0
      add :discount_cents, :integer, null: false, default: 0
      add :total_cents, :integer, null: false, default: 0
      add :package_code_snapshot, :string
      add :package_family_snapshot, :string
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:finance_invoice_lines, [:finance_invoice_id])
    create index(:finance_invoice_lines, [:membership_package_subscription_id])

    create constraint(:finance_invoice_lines, :finance_invoice_lines_type_check,
             check:
               "line_type IN ('membership_package', 'manual_charge', 'discount', 'adjustment')"
           )

    create constraint(:finance_invoice_lines, :finance_invoice_lines_amounts_check,
             check:
               "quantity > 0 AND unit_amount_cents >= 0 AND discount_cents >= 0 AND total_cents >= 0"
           )

    alter table(:membership_payments) do
      add :finance_invoice_id,
          references(:finance_invoices, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:membership_payments, [:finance_invoice_id])

    alter table(:finance_credit_ledger_entries) do
      add :finance_invoice_id,
          references(:finance_invoices, type: :binary_id, on_delete: :nilify_all)

      add :finance_invoice_line_id,
          references(:finance_invoice_lines, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:finance_credit_ledger_entries, [:finance_invoice_id])
    create index(:finance_credit_ledger_entries, [:finance_invoice_line_id])

    alter table(:memberships) do
      add :entitlement_status, :string, null: false, default: "inactive"
      add :entitlement_source, :string
      add :entitlement_expires_on, :date
      add :entitlement_updated_at, :utc_datetime_usec
    end

    create index(:memberships, [:entitlement_status])

    create constraint(:memberships, :memberships_entitlement_status_check,
             check: "entitlement_status IN ('active', 'grace', 'blocked', 'inactive')"
           )
  end
end
