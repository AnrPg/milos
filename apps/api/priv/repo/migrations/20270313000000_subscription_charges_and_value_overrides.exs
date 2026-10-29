defmodule Palee.Repo.Migrations.SubscriptionChargesAndValueOverrides do
  @moduledoc """
  ADR-274: a member's status and dates are worked out from their
  subscriptions and charges; what staff set by hand is kept with its history.

    * `memberships.status_shown`: the status staff see (money folded in,
      `MemberStatus`); `status` keeps the lifecycle every rule reads.
    * `membership_package_subscriptions.charges_from`: the first period
      start Palee bills by itself (nil: never).
    * `finance_invoices.invoice_type` admits `subscription` (the charge for
      a subscription's first period), one per subscription.
    * `finance_value_overrides`: values staff set by hand, never deleted.

  Running subscriptions with a price are billed from the start of their
  current period, so a member who never paid shows up at once.
  """

  use Ecto.Migration

  @statuses ~w(active trial comped unpaid overdue leaving expiring paused expired cancelled no_package)

  def up do
    alter table(:memberships) do
      add :status_shown, :string
    end

    create constraint(:memberships, :memberships_status_shown_check,
             check: "status_shown IS NULL OR status_shown IN (#{quoted(@statuses)})"
           )

    alter table(:membership_package_subscriptions) do
      add :charges_from, :date
    end

    drop constraint(:finance_invoices, :finance_invoices_type_check)

    create constraint(:finance_invoices, :finance_invoices_type_check,
             check: "invoice_type IN ('manual', 'renewal', 'adjustment', 'subscription')"
           )

    create unique_index(:finance_invoices, [:membership_package_subscription_id],
             name: :finance_subscription_charges_unique_index,
             where:
               "invoice_type = 'subscription' AND status <> 'void' AND deleted_at IS NULL AND membership_package_subscription_id IS NOT NULL"
           )

    create table(:finance_value_overrides, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :subject_type, :string, null: false
      add :subject_id, :binary_id, null: false
      add :field, :string, null: false
      add :computed_value, :string
      add :value, :string, null: false
      add :reason, :string, size: 500
      add :set_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :ended_at, :utc_datetime_usec
      add :ended_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :end_reason, :string
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:finance_value_overrides, :finance_value_overrides_field_check,
             check:
               "(field = 'status' AND subject_type = 'membership') OR (field = 'ends_on' AND subject_type = 'subscription')"
           )

    create constraint(:finance_value_overrides, :finance_value_overrides_end_check,
             check:
               "(ended_at IS NULL AND end_reason IS NULL) OR (ended_at IS NOT NULL AND end_reason IN ('reset', 'replaced', 'lapsed'))"
           )

    create unique_index(:finance_value_overrides, [:subject_id, :field],
             name: :finance_value_overrides_in_force_index,
             where: "ended_at IS NULL"
           )

    create index(:finance_value_overrides, [:organization_id, :membership_id, :inserted_at])

    execute("""
    CREATE TRIGGER finance_value_overrides_apply_tenant_context
    BEFORE INSERT OR UPDATE ON finance_value_overrides
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY finance_value_overrides_tenant_policy ON finance_value_overrides
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE finance_value_overrides ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE finance_value_overrides FORCE ROW LEVEL SECURITY")

    # Running subscriptions with a price are billed from the start of the
    # period they are in now (recurring) or from their start (the others);
    # the hourly charge run issues the charges.
    execute("""
    UPDATE membership_package_subscriptions s
    SET charges_from = CASE
      WHEN s.billing_period_snapshot IN ('monthly', 'quarterly', 'semiannual', 'annual') THEN
        (s.starts_on + make_interval(months =>
          (FLOOR((EXTRACT(YEAR FROM age(CURRENT_DATE, s.starts_on)) * 12
                 + EXTRACT(MONTH FROM age(CURRENT_DATE, s.starts_on)))
                 / p.months) * p.months)::int))::date
      ELSE s.starts_on
    END
    FROM (VALUES ('monthly', 1), ('quarterly', 3), ('semiannual', 6), ('annual', 12),
                 ('one_off', 1), ('custom', 1), ('with_base', 1)) AS p(period, months)
    WHERE p.period = s.billing_period_snapshot
      AND s.status = 'active'
      AND s.price_cents_snapshot > 0
      AND s.corporate_client_id IS NULL
      AND s.starts_on IS NOT NULL
      AND s.starts_on <= CURRENT_DATE
      AND (s.ends_on IS NULL OR s.ends_on >= CURRENT_DATE)
    """)
  end

  def down do
    execute(
      "UPDATE finance_invoices SET invoice_type = 'manual' WHERE invoice_type = 'subscription'"
    )

    drop table(:finance_value_overrides)

    drop index(:finance_invoices, [:membership_package_subscription_id],
           name: :finance_subscription_charges_unique_index
         )

    drop constraint(:finance_invoices, :finance_invoices_type_check)

    create constraint(:finance_invoices, :finance_invoices_type_check,
             check: "invoice_type IN ('manual', 'renewal', 'adjustment')"
           )

    alter table(:membership_package_subscriptions) do
      remove :charges_from
    end

    drop constraint(:memberships, :memberships_status_shown_check)

    alter table(:memberships) do
      remove :status_shown
    end
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
