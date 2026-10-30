defmodule Palee.Repo.Migrations.CreateFiscalTransmissions do
  @moduledoc """
  ADR-243: reporting fiscal documents to the tax authority (myDATA).

    * `fiscal_authority_connections` – one per organization and authority:
      environment and credentials (the subscription key encrypted with
      `DataCipher`, ADR-161);
    * `fiscal_transmissions` – the outbox: one row per document that must
      be reported, with its state and, once accepted, the MARK;
    * `fiscal_transmission_attempts` – insert-only log of every call with
      what was sent and received (kept with the documents).
  """

  use Ecto.Migration

  @tables ~w(fiscal_authority_connections fiscal_transmissions fiscal_transmission_attempts)

  def up do
    create table(:fiscal_authority_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :authority, :string, null: false
      add :environment, :string, null: false
      add :user_id, :string
      add :subscription_key, :binary
      add :status, :string, null: false, default: "active"
      add :last_error, :string, size: 500
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fiscal_authority_connections, [:organization_id, :authority])

    create constraint(:fiscal_authority_connections, :fiscal_authority_connections_check,
             check: """
             authority IN ('mydata') AND environment IN ('sandbox', 'test', 'production')
             AND status IN ('active', 'invalid')
             AND (environment = 'sandbox' OR (user_id IS NOT NULL AND subscription_key IS NOT NULL))
             """
           )

    create table(:fiscal_transmissions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :document_id, :binary_id, null: false
      add :authority, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec
      add :claimed_at, :utc_datetime_usec
      add :environment, :string
      add :mark, :string
      add :uid, :string
      add :authentication_code, :string
      add :qr_url, :string, size: 1000
      add :accepted_at, :utc_datetime_usec
      add :last_error_code, :string, size: 60
      add :last_error_message, :string, size: 1000
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE fiscal_transmissions
    ADD CONSTRAINT fiscal_transmissions_document_fkey
    FOREIGN KEY (document_id, organization_id)
    REFERENCES fiscal_documents (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:fiscal_transmissions, [:id, :organization_id],
             name: :fiscal_transmissions_id_organization_index
           )

    create unique_index(:fiscal_transmissions, [:document_id, :authority])

    create index(:fiscal_transmissions, [:next_attempt_at],
             where: "status = 'pending'",
             name: :fiscal_transmissions_due_index
           )

    create index(:fiscal_transmissions, [:organization_id, :status])

    create constraint(:fiscal_transmissions, :fiscal_transmissions_check,
             check: """
             authority IN ('mydata')
             AND status IN ('pending', 'sending', 'accepted', 'rejected', 'failed')
             AND attempts >= 0
             AND (status <> 'accepted' OR mark IS NOT NULL)
             """
           )

    create table(:fiscal_transmission_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :transmission_id, :binary_id, null: false
      add :attempt, :integer, null: false
      add :environment, :string, null: false
      add :outcome, :string, null: false
      add :request_body, :text
      add :response_status, :integer
      add :response_body, :text
      add :error, :string, size: 1000
      add :duration_ms, :integer
      add :started_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE fiscal_transmission_attempts
    ADD CONSTRAINT fiscal_transmission_attempts_transmission_fkey
    FOREIGN KEY (transmission_id, organization_id)
    REFERENCES fiscal_transmissions (id, organization_id) ON DELETE CASCADE
    """)

    create index(:fiscal_transmission_attempts, [:transmission_id, :started_at])

    create constraint(:fiscal_transmission_attempts, :fiscal_transmission_attempts_check,
             check: "outcome IN ('accepted', 'rejected', 'unauthorized', 'transient', 'deferred')"
           )

    execute("""
    CREATE TRIGGER fiscal_transmission_attempts_immutable
    BEFORE UPDATE OR DELETE ON fiscal_transmission_attempts
    FOR EACH ROW EXECUTE FUNCTION palee_fiscal_immutable()
    """)

    for table <- @tables do
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

  def down do
    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))
  end
end
