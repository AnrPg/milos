defmodule MilosTraining.Repo.Migrations.AddAddOnsSharedAndCorporate do
  use Ecto.Migration

  # ADR-098: add-ons follow a base subscription, shared memberships have
  # beneficiaries, and corporate clients pay for seats.

  def up do
    create unique_index(:membership_package_subscriptions, [:id, :organization_id],
             name: :membership_package_subscriptions_id_organization_index
           )

    alter table(:membership_package_subscriptions) do
      add :base_subscription_id, :binary_id
      add :corporate_client_id, :binary_id
    end

    execute("""
    ALTER TABLE membership_package_subscriptions
    ADD CONSTRAINT membership_package_subscriptions_base_fkey
    FOREIGN KEY (base_subscription_id, organization_id)
    REFERENCES membership_package_subscriptions (id, organization_id) ON DELETE CASCADE
    """)

    create index(:membership_package_subscriptions, [:base_subscription_id],
             where: "base_subscription_id IS NOT NULL"
           )

    create table(:finance_subscription_beneficiaries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_package_subscription_id, :binary_id, null: false

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :is_minor, :boolean, null: false, default: false
      add :added_by_id, :binary_id
      add :removed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE finance_subscription_beneficiaries
    ADD CONSTRAINT finance_subscription_beneficiaries_subscription_fkey
    FOREIGN KEY (membership_package_subscription_id, organization_id)
    REFERENCES membership_package_subscriptions (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(
             :finance_subscription_beneficiaries,
             [:membership_package_subscription_id, :membership_id],
             where: "removed_at IS NULL",
             name: :finance_subscription_beneficiaries_active_index
           )

    create index(:finance_subscription_beneficiaries, [:membership_id],
             where: "removed_at IS NULL"
           )

    enable_tenant_rls("finance_subscription_beneficiaries")

    create table(:finance_corporate_clients, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_package_id,
          references(:membership_packages, type: :binary_id, on_delete: :restrict),
          null: false

      add :company_name, :string, null: false
      add :billing_email, :string
      add :contact_name, :string
      add :enrollment_code, :string, null: false
      add :status, :string, null: false, default: "active"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:finance_corporate_clients, [:id, :organization_id],
             name: :finance_corporate_clients_id_organization_index
           )

    create unique_index(:finance_corporate_clients, [:organization_id, :membership_package_id],
             name: :finance_corporate_clients_package_index
           )

    create unique_index(:finance_corporate_clients, [:organization_id, :enrollment_code],
             name: :finance_corporate_clients_code_index
           )

    create constraint(:finance_corporate_clients, :finance_corporate_clients_status,
             check: "status IN ('active', 'archived')"
           )

    enable_tenant_rls("finance_corporate_clients")

    execute("""
    ALTER TABLE membership_package_subscriptions
    ADD CONSTRAINT membership_package_subscriptions_corporate_client_fkey
    FOREIGN KEY (corporate_client_id, organization_id)
    REFERENCES finance_corporate_clients (id, organization_id)
    """)

    create index(:membership_package_subscriptions, [:corporate_client_id],
             where: "corporate_client_id IS NOT NULL"
           )

    create table(:finance_corporate_invoices, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :corporate_client_id, :binary_id, null: false
      add :period_start, :date, null: false
      add :period_end, :date, null: false
      add :seat_billing, :string, null: false
      add :seats_billed, :integer, null: false
      add :unit_price_cents, :integer, null: false
      add :total_cents, :integer, null: false
      add :status, :string, null: false, default: "issued"
      add :issued_on, :date, null: false
      add :paid_on, :date
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE finance_corporate_invoices
    ADD CONSTRAINT finance_corporate_invoices_client_fkey
    FOREIGN KEY (corporate_client_id, organization_id)
    REFERENCES finance_corporate_clients (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:finance_corporate_invoices, [:corporate_client_id, :period_start],
             name: :finance_corporate_invoices_period_index
           )

    create constraint(:finance_corporate_invoices, :finance_corporate_invoices_status,
             check: "status IN ('issued', 'paid', 'void')"
           )

    enable_tenant_rls("finance_corporate_invoices")
  end

  def down do
    drop table(:finance_corporate_invoices)

    execute(
      "ALTER TABLE membership_package_subscriptions DROP CONSTRAINT IF EXISTS membership_package_subscriptions_corporate_client_fkey"
    )

    drop table(:finance_corporate_clients)
    drop table(:finance_subscription_beneficiaries)

    execute(
      "ALTER TABLE membership_package_subscriptions DROP CONSTRAINT IF EXISTS membership_package_subscriptions_base_fkey"
    )

    alter table(:membership_package_subscriptions) do
      remove :corporate_client_id
      remove :base_subscription_id
    end

    drop index(:membership_package_subscriptions, [:id, :organization_id],
           name: :membership_package_subscriptions_id_organization_index
         )
  end

  defp enable_tenant_rls(table) do
    execute("""
    CREATE TRIGGER #{table}_apply_tenant_context
    BEFORE INSERT OR UPDATE ON #{table}
    FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
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
