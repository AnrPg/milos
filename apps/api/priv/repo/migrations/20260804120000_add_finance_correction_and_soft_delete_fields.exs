defmodule MilosTraining.Repo.Migrations.AddFinanceCorrectionAndSoftDeleteFields do
  use Ecto.Migration

  def up do
    drop constraint(:finance_invoices, :finance_invoices_status_check)

    create constraint(:finance_invoices, :finance_invoices_status_check,
             check:
               "status IN ('draft', 'issued', 'partially_paid', 'paid', 'overdue', 'partially_refunded', 'refunded', 'void')"
           )

    alter table(:finance_invoices) do
      add_if_not_exists :deleted_at, :utc_datetime_usec

      add_if_not_exists :deleted_by_id,
                        references(:users, type: :binary_id, on_delete: :nilify_all)

      add_if_not_exists :deletion_reason, :text
    end

    create_if_not_exists index(:finance_invoices, [:deleted_at])

    alter table(:membership_payments) do
      add_if_not_exists :deleted_at, :utc_datetime_usec

      add_if_not_exists :deleted_by_id,
                        references(:users, type: :binary_id, on_delete: :nilify_all)

      add_if_not_exists :deletion_reason, :text
    end

    create_if_not_exists index(:membership_payments, [:deleted_at])

    alter table(:finance_payment_reversals) do
      add_if_not_exists :deleted_at, :utc_datetime_usec

      add_if_not_exists :deleted_by_id,
                        references(:users, type: :binary_id, on_delete: :nilify_all)

      add_if_not_exists :deletion_reason, :text
    end

    create_if_not_exists index(:finance_payment_reversals, [:deleted_at])

    alter table(:finance_credit_ledger_entries) do
      add_if_not_exists :deleted_at, :utc_datetime_usec

      add_if_not_exists :deleted_by_id,
                        references(:users, type: :binary_id, on_delete: :nilify_all)

      add_if_not_exists :deletion_reason, :text
    end

    create_if_not_exists index(:finance_credit_ledger_entries, [:deleted_at])
  end

  def down do
    drop index(:finance_credit_ledger_entries, [:deleted_at])

    alter table(:finance_credit_ledger_entries) do
      remove :deletion_reason
      remove :deleted_by_id
      remove :deleted_at
    end

    drop index(:finance_payment_reversals, [:deleted_at])

    alter table(:finance_payment_reversals) do
      remove :deletion_reason
      remove :deleted_by_id
      remove :deleted_at
    end

    drop index(:membership_payments, [:deleted_at])

    alter table(:membership_payments) do
      remove :deletion_reason
      remove :deleted_by_id
      remove :deleted_at
    end

    drop index(:finance_invoices, [:deleted_at])

    alter table(:finance_invoices) do
      remove :deletion_reason
      remove :deleted_by_id
      remove :deleted_at
    end

    drop constraint(:finance_invoices, :finance_invoices_status_check)

    create constraint(:finance_invoices, :finance_invoices_status_check,
             check: "status IN ('draft', 'issued', 'partially_paid', 'paid', 'overdue', 'void')"
           )
  end
end
