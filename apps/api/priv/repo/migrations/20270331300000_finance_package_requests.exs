defmodule Palee.Repo.Migrations.FinancePackageRequests do
  @moduledoc """
  ADR-291: a package a person asked for in the app, waiting to be paid at
  the box's front desk («Περιμένει πληρωμή»). It is not a subscription: it
  grants nothing and owes nothing until the desk takes the money, which
  assigns the package in the same step. A request is held for 14 days.
  """

  use Ecto.Migration

  def change do
    create table(:finance_package_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :membership_package_id,
          references(:membership_packages, type: :binary_id, on_delete: :delete_all),
          null: false

      add :package_name_snapshot, :string, null: false
      add :price_cents_snapshot, :integer, null: false
      add :currency, :string, size: 3, null: false
      add :status, :string, null: false, default: "pending"
      add :source, :string, null: false, default: "member"
      add :requested_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :hold_until, :date, null: false
      add :closed_at, :utc_datetime_usec
      add :closed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :membership_package_subscription_id,
          references(:membership_package_subscriptions, type: :binary_id, on_delete: :nilify_all)

      add :membership_payment_id,
          references(:membership_payments, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:finance_package_requests, :finance_package_requests_status_check,
             check: "status IN ('pending', 'activated', 'cancelled', 'lapsed')"
           )

    create constraint(:finance_package_requests, :finance_package_requests_source_check,
             check: "source IN ('member', 'staff')"
           )

    create constraint(:finance_package_requests, :finance_package_requests_price_check,
             check: "price_cents_snapshot > 0"
           )

    create constraint(:finance_package_requests, :finance_package_requests_closed_check,
             check: "(status = 'pending') = (closed_at IS NULL)"
           )

    # One open request per person and package: asking again returns it.
    create unique_index(
             :finance_package_requests,
             [:organization_id, :user_id, :membership_package_id],
             name: :finance_package_requests_one_pending_index,
             where: "status = 'pending'"
           )

    create index(:finance_package_requests, [:organization_id, :status, :hold_until])
    create index(:finance_package_requests, [:user_id])

    execute(
      """
      CREATE TRIGGER finance_package_requests_apply_tenant_context
      BEFORE INSERT OR UPDATE ON finance_package_requests
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """,
      "DROP TRIGGER IF EXISTS finance_package_requests_apply_tenant_context ON finance_package_requests"
    )

    execute(
      """
      CREATE POLICY finance_package_requests_tenant_policy ON finance_package_requests
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS finance_package_requests_tenant_policy ON finance_package_requests"
    )

    execute(
      "ALTER TABLE finance_package_requests ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE finance_package_requests DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE finance_package_requests FORCE ROW LEVEL SECURITY",
      "ALTER TABLE finance_package_requests NO FORCE ROW LEVEL SECURITY"
    )
  end
end
