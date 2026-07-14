defmodule MilosTraining.Repo.Migrations.CreateFinancePaymentReversals do
  use Ecto.Migration

  def change do
    create table(:finance_payment_reversals, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :membership_payment_id,
          references(:membership_payments, type: :binary_id, on_delete: :delete_all),
          null: false

      add :finance_invoice_id,
          references(:finance_invoices, type: :binary_id, on_delete: :nilify_all)

      add :reversal_type, :string, null: false, default: "refund"
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false, default: "EUR"
      add :occurred_on, :date, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :reason, :text
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :idempotency_key, :string, null: false
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:finance_payment_reversals, [:idempotency_key])
    create index(:finance_payment_reversals, [:membership_id, :occurred_at])
    create index(:finance_payment_reversals, [:membership_payment_id])
    create index(:finance_payment_reversals, [:finance_invoice_id])
    create index(:finance_payment_reversals, [:created_by_id])

    create constraint(:finance_payment_reversals, :finance_payment_reversals_type_check,
             check: "reversal_type IN ('refund', 'payment_reversal', 'waiver_reversal')"
           )

    create constraint(:finance_payment_reversals, :finance_payment_reversals_amount_check,
             check: "amount_cents > 0"
           )

    alter table(:finance_credit_ledger_entries) do
      add :reversed_credit_ledger_entry_id,
          references(:finance_credit_ledger_entries, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:finance_credit_ledger_entries, [:reversed_credit_ledger_entry_id])
  end
end
