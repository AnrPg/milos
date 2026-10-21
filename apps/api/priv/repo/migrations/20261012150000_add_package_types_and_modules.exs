defmodule Palee.Repo.Migrations.AddPackageTypesAndModules do
  use Ecto.Migration

  @types ~w[membership class_pack drop_in trial pt_pack add_on shared corporate]
  @billing_periods ~w[monthly quarterly semiannual annual custom one_off with_base]

  def up do
    alter table(:membership_packages) do
      add :package_type, :string, null: false, default: "membership"
    end

    create constraint(:membership_packages, :membership_packages_package_type,
             check: "package_type IN (#{quoted(@types)})"
           )

    create constraint(:membership_packages, :membership_packages_billing_period,
             check: "billing_period IN (#{quoted(@billing_periods)})"
           )

    # ADR-096: family becomes the reporting label of the package type. Every
    # legacy package is a recurring membership and ADR-040 guaranteed that the
    # family value carried no authorization meaning.
    execute("UPDATE membership_packages SET family = package_type")

    execute("""
    UPDATE membership_package_subscriptions
    SET package_family_snapshot = 'membership'
    WHERE package_family_snapshot IS DISTINCT FROM 'membership'
    """)

    execute("""
    UPDATE finance_invoice_lines
    SET package_family_snapshot = 'membership'
    WHERE package_family_snapshot IS NOT NULL
      AND package_family_snapshot <> 'membership'
    """)

    alter table(:finance_settings) do
      add :package_modules, {:array, :string},
        null: false,
        default: fragment("ARRAY['group_classes', 'online_coaching']::varchar[]")
    end

    drop constraint(:finance_entitlement_usage_entries, :entitlement_usage_allowance_key)

    create constraint(:finance_entitlement_usage_entries, :entitlement_usage_allowance_key,
             check:
               "allowance_key IN ('class_visits', 'coaching_touchpoints') OR " <>
                 "allowance_key ~ '^class_visits:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'"
           )
  end

  def down do
    drop constraint(:finance_entitlement_usage_entries, :entitlement_usage_allowance_key)

    # The ledger is append-only, so per-class-type entries are kept and the
    # original constraint is restored for new rows only.
    create constraint(:finance_entitlement_usage_entries, :entitlement_usage_allowance_key,
             check: "allowance_key IN ('class_visits', 'coaching_touchpoints')",
             validate: false
           )

    alter table(:finance_settings) do
      remove :package_modules
    end

    drop constraint(:membership_packages, :membership_packages_billing_period)
    drop constraint(:membership_packages, :membership_packages_package_type)

    alter table(:membership_packages) do
      remove :package_type
    end
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
