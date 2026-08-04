defmodule MilosTraining.Repo.Migrations.FinalizeFinanceT4TenantBoundaries do
  use Ecto.Migration

  @finance_tables ~w(
    membership_packages memberships membership_package_subscriptions
    membership_payments promotion_campaigns promotion_codes promotion_redemptions
    referral_programs referral_events referral_rewards finance_invoices
    finance_invoice_lines finance_payment_reversals finance_credit_ledger_entries
    finance_entitlement_usage_entries finance_settings
  )

  def up do
    scope_finance_uniqueness()

    Enum.each(@finance_tables, fn table ->
      execute("DROP TRIGGER IF EXISTS #{table}_apply_tenant_context ON #{table}")

      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
      """)

      execute("DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}")

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (
        organization_id = COALESCE(
          NULLIF(current_setting('app.organization_id', true), '')::uuid,
          milos_legacy_organization_id()
        )
      )
      WITH CHECK (
        organization_id = COALESCE(
          NULLIF(current_setting('app.organization_id', true), '')::uuid,
          milos_legacy_organization_id()
        )
      )
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end)
  end

  def down do
    Enum.each(@finance_tables, fn table ->
      execute("ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY")
      execute("DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}")
      execute("DROP TRIGGER IF EXISTS #{table}_apply_tenant_context ON #{table}")
    end)

    restore_global_finance_uniqueness()
  end

  defp scope_finance_uniqueness do
    drop_if_exists unique_index(:membership_packages, [:code])

    drop_if_exists unique_index(:membership_packages, [:organization_id, :code],
                     name: :membership_packages_organization_code_index
                   )

    create unique_index(:membership_packages, [:organization_id, :code],
             name: :membership_packages_organization_code_index
           )

    drop_if_exists unique_index(:memberships, [:user_id])

    drop_if_exists unique_index(:memberships, [:organization_id, :user_id],
                     name: :memberships_organization_user_index
                   )

    create unique_index(:memberships, [:organization_id, :user_id],
             name: :memberships_organization_user_index
           )

    drop_if_exists unique_index(:promotion_codes, [:code])

    drop_if_exists unique_index(:promotion_codes, [:organization_id, :code],
                     name: :promotion_codes_organization_code_index
                   )

    create unique_index(:promotion_codes, [:organization_id, :code],
             name: :promotion_codes_organization_code_index
           )

    drop_if_exists unique_index(:finance_invoices, [:invoice_number])

    drop_if_exists unique_index(:finance_invoices, [:organization_id, :invoice_number],
                     name: :finance_invoices_organization_invoice_number_index
                   )

    create unique_index(:finance_invoices, [:organization_id, :invoice_number],
             name: :finance_invoices_organization_invoice_number_index
           )

    drop_if_exists unique_index(:finance_credit_ledger_entries, [:idempotency_key])

    drop_if_exists unique_index(
                     :finance_credit_ledger_entries,
                     [:organization_id, :idempotency_key],
                     name: :finance_credit_entries_organization_idempotency_key_index
                   )

    create unique_index(:finance_credit_ledger_entries, [:organization_id, :idempotency_key],
             name: :finance_credit_entries_organization_idempotency_key_index,
             where: "idempotency_key IS NOT NULL"
           )

    drop_if_exists unique_index(:finance_entitlement_usage_entries, [:idempotency_key])

    drop_if_exists unique_index(
                     :finance_entitlement_usage_entries,
                     [:organization_id, :idempotency_key],
                     name: :finance_entitlement_usage_organization_idempotency_key_index
                   )

    create unique_index(:finance_entitlement_usage_entries, [:organization_id, :idempotency_key],
             name: :finance_entitlement_usage_organization_idempotency_key_index
           )
  end

  defp restore_global_finance_uniqueness do
    drop_if_exists unique_index(:membership_packages, [:organization_id, :code],
                     name: :membership_packages_organization_code_index
                   )

    create unique_index(:membership_packages, [:code])

    drop_if_exists unique_index(:memberships, [:organization_id, :user_id],
                     name: :memberships_organization_user_index
                   )

    create unique_index(:memberships, [:user_id])

    drop_if_exists unique_index(:promotion_codes, [:organization_id, :code],
                     name: :promotion_codes_organization_code_index
                   )

    create unique_index(:promotion_codes, [:code])

    drop_if_exists unique_index(:finance_invoices, [:organization_id, :invoice_number],
                     name: :finance_invoices_organization_invoice_number_index
                   )

    create unique_index(:finance_invoices, [:invoice_number])

    drop_if_exists unique_index(
                     :finance_credit_ledger_entries,
                     [:organization_id, :idempotency_key],
                     name: :finance_credit_entries_organization_idempotency_key_index
                   )

    create unique_index(:finance_credit_ledger_entries, [:idempotency_key])

    drop_if_exists unique_index(
                     :finance_entitlement_usage_entries,
                     [:organization_id, :idempotency_key],
                     name: :finance_entitlement_usage_organization_idempotency_key_index
                   )

    create unique_index(:finance_entitlement_usage_entries, [:idempotency_key])
  end
end
