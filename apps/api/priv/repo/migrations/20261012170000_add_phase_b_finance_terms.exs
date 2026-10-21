defmodule Palee.Repo.Migrations.AddPhaseBFinanceTerms do
  use Ecto.Migration

  # ADR-097: commitment, activation on first use, freezes, member discounts and
  # the ledger keys for events, guest passes and open gym.

  @class_type_key "allowance_key ~ '^class_visits:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'"

  def up do
    alter table(:membership_package_subscriptions) do
      add :commitment_ends_on, :date
      add :activated_on, :date
    end

    create table(:finance_subscription_freezes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_package_subscription_id,
          references(:membership_package_subscriptions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :starts_on, :date, null: false
      add :ends_on, :date, null: false
      add :extension_days, :integer, null: false, default: 0
      add :reason, :text, null: false
      add :admin_id, :binary_id
      add :cancelled_at, :utc_datetime_usec
      add :cancel_reason, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:finance_subscription_freezes, [:membership_id, :starts_on])
    create index(:finance_subscription_freezes, [:membership_package_subscription_id])

    create constraint(:finance_subscription_freezes, :finance_subscription_freezes_dates,
             check: "ends_on >= starts_on"
           )

    enable_tenant_rls("finance_subscription_freezes")

    alter table(:finance_invoice_lines) do
      add :charge_category, :string
      add :member_discount_percent, :integer
    end

    create constraint(:finance_invoice_lines, :finance_invoice_lines_charge_category,
             check:
               "charge_category IS NULL OR charge_category IN ('product', 'personal_training', 'event', 'other')"
           )

    replace_allowance_keys(
      "'class_visits', 'coaching_touchpoints', 'event_visits', 'guest_passes', 'open_gym_visits'",
      true
    )
  end

  def down do
    # The ledger is append-only: Phase B entries are kept and the previous
    # constraint applies to new rows only.
    replace_allowance_keys("'class_visits', 'coaching_touchpoints'", false)

    drop constraint(:finance_invoice_lines, :finance_invoice_lines_charge_category)

    alter table(:finance_invoice_lines) do
      remove :member_discount_percent
      remove :charge_category
    end

    drop table(:finance_subscription_freezes)

    alter table(:membership_package_subscriptions) do
      remove :activated_on
      remove :commitment_ends_on
    end
  end

  defp replace_allowance_keys(keys, validate?) do
    drop constraint(:finance_entitlement_usage_entries, :entitlement_usage_allowance_key)

    create constraint(:finance_entitlement_usage_entries, :entitlement_usage_allowance_key,
             check: "allowance_key IN (#{keys}) OR #{@class_type_key}",
             validate: validate?
           )
  end

  defp enable_tenant_rls(table) do
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
end
