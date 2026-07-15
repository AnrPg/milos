defmodule MilosTraining.Repo.Migrations.CreateFinanceEntitlementUsageEntries do
  use Ecto.Migration

  def change do
    alter table(:finance_settings) do
      add :entitlement_enforcement_mode, :string, null: false, default: "observe"
      add :entitlement_timezone, :string, null: false, default: "Europe/Athens"
    end

    create constraint(:finance_settings, :finance_settings_entitlement_enforcement_mode,
             check: "entitlement_enforcement_mode IN ('observe', 'enforce_managed', 'enforce_all')"
           )

    create table(:finance_entitlement_usage_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :membership_id,
          references(:memberships, type: :binary_id, on_delete: :restrict),
          null: false

      add :membership_package_subscription_id,
          references(:membership_package_subscriptions, type: :binary_id, on_delete: :restrict),
          null: false

      add :allowance_key, :string, null: false
      add :event_type, :string, null: false
      add :quantity_delta, :integer, null: false
      add :period_start, :date, null: false
      add :period_end, :date, null: false
      add :source_context, :string, null: false
      add :source_id, :binary_id

      add :parent_entry_id,
          references(:finance_entitlement_usage_entries, type: :binary_id, on_delete: :restrict)

      add :admin_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reason, :text
      add :idempotency_key, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:finance_entitlement_usage_entries, :entitlement_usage_allowance_key,
             check: "allowance_key IN ('class_visits', 'coaching_touchpoints')"
           )

    create constraint(:finance_entitlement_usage_entries, :entitlement_usage_event_type,
             check: "event_type IN ('reserve', 'finalize', 'release', 'consume', 'adjustment')"
           )

    create constraint(:finance_entitlement_usage_entries, :entitlement_usage_period,
             check: "period_end >= period_start"
           )

    create unique_index(:finance_entitlement_usage_entries, [:idempotency_key])

    create index(:finance_entitlement_usage_entries, [
             :membership_package_subscription_id,
             :allowance_key,
             :period_start,
             :period_end
           ])

    create unique_index(:finance_entitlement_usage_entries, [:parent_entry_id],
             where: "event_type IN ('finalize', 'release')",
             name: :entitlement_usage_one_terminal_transition
           )
  end
end
