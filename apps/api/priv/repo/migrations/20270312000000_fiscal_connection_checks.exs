defmodule Palee.Repo.Migrations.FiscalConnectionChecks do
  @moduledoc """
  ADR-273: «Δοκιμή σύνδεσης» for every fiscal connection and who manages
  a box's connections.

    * The three connection tables (myDATA and the AADE registry, Peppol,
      the till devices) get the result of their last check: a stable
      `error_code` the screens turn into a plain message (the free-text
      `last_error` stays for support only), `checked_at`, `next_check_at`
      (every 3 months, sooner after a failure), `check_failures` and
      `updated_by_platform` (saved by the Palee team from the vendor
      console).
    * `fiscal_connection_settings`: one row per organization saying who
      manages its connections (`owner` or `palee`).
    * Notification type `fiscal_connection_failed` for the staff who
      manage billing.
  """

  use Ecto.Migration

  @connection_tables ~w(fiscal_authority_connections fiscal_network_connections fiscal_till_connections)a
  @types ~w(fiscal_connection_failed)

  def up do
    for table <- @connection_tables do
      alter table(table) do
        add :error_code, :string, size: 60
        add :checked_at, :utc_datetime_usec
        add :next_check_at, :utc_datetime_usec
        add :check_failures, :integer, null: false, default: 0
        add :updated_by_platform, :boolean, null: false, default: false
      end

      create constraint(table, :"#{table}_check_failures_check", check: "check_failures >= 0")
    end

    create table(:fiscal_connection_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :managed_by, :string, null: false, default: "owner"
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fiscal_connection_settings, [:organization_id])

    create constraint(:fiscal_connection_settings, :fiscal_connection_settings_managed_by_check,
             check: "managed_by IN ('owner', 'palee')"
           )

    execute("""
    CREATE TRIGGER fiscal_connection_settings_apply_tenant_context
    BEFORE INSERT OR UPDATE ON fiscal_connection_settings
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY fiscal_connection_settings_tenant_policy ON fiscal_connection_settings
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE fiscal_connection_settings ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE fiscal_connection_settings FORCE ROW LEVEL SECURITY")

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN ('fiscal_connection_failed')")
    rewrite_notification_types(&(&1 -- @types))

    drop table(:fiscal_connection_settings)

    for table <- @connection_tables do
      drop constraint(table, :"#{table}_check_failures_check")

      alter table(table) do
        remove :error_code
        remove :checked_at
        remove :next_check_at
        remove :check_failures
        remove :updated_by_platform
      end
    end
  end

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{Enum.map_join(change.(current), ", ", &"'#{&1}'")}))"
    )
  end
end
