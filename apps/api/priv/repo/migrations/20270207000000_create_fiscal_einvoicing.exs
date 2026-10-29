defmodule Palee.Repo.Migrations.CreateFiscalEinvoicing do
  @moduledoc """
  ADR-250: sending B2B invoices and credit notes over Peppol.

    * `fiscal_network_connections` – one per organization and network: the
      access point provider, environment, the business's Peppol identifier
      and, outside the sandbox, its credentials (API key encrypted with
      `DataCipher`, ADR-161, never returned);
    * `fiscal_einvoice_submissions` – the outbox: one row per document sent
      over the network, with its state, the provider's submission id and the
      idempotency GUID that makes a resend safe;
    * `fiscal_einvoice_attempts` – insert-only log of every call (submit or
      status poll) with what was sent and received.
  """

  use Ecto.Migration

  @tables ~w(fiscal_network_connections fiscal_einvoice_submissions fiscal_einvoice_attempts)

  def up do
    create table(:fiscal_network_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :network, :string, null: false
      add :provider, :string, null: false
      add :environment, :string, null: false
      add :peppol_scheme, :string, null: false
      add :peppol_identifier, :string, null: false
      add :legal_entity_id, :string
      add :api_key, :binary
      add :webhook_token_hash, :string
      add :status, :string, null: false, default: "active"
      add :last_error, :string, size: 500
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fiscal_network_connections, [:organization_id, :network])

    create constraint(:fiscal_network_connections, :fiscal_network_connections_check,
             check: """
             network IN ('peppol') AND provider IN ('sandbox', 'storecove')
             AND environment IN ('sandbox', 'test', 'production')
             AND status IN ('active', 'invalid')
             AND (provider = 'sandbox') = (environment = 'sandbox')
             AND (environment = 'sandbox' OR (api_key IS NOT NULL AND legal_entity_id IS NOT NULL))
             """
           )

    create table(:fiscal_einvoice_submissions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :document_id, :binary_id, null: false
      add :network, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :polls, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec
      add :claimed_at, :utc_datetime_usec
      add :environment, :string
      add :idempotency_guid, :binary_id, null: false
      add :recipient_scheme, :string, null: false
      add :recipient_identifier, :string, null: false
      add :provider_submission_id, :string
      add :submitted_at, :utc_datetime_usec
      add :delivered_at, :utc_datetime_usec
      add :last_error_code, :string, size: 60
      add :last_error_message, :string, size: 1000
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE fiscal_einvoice_submissions
    ADD CONSTRAINT fiscal_einvoice_submissions_document_fkey
    FOREIGN KEY (document_id, organization_id)
    REFERENCES fiscal_documents (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:fiscal_einvoice_submissions, [:id, :organization_id],
             name: :fiscal_einvoice_submissions_id_organization_index
           )

    create unique_index(:fiscal_einvoice_submissions, [:document_id, :network])
    create unique_index(:fiscal_einvoice_submissions, [:idempotency_guid])

    create index(:fiscal_einvoice_submissions, [:next_attempt_at],
             where: "status IN ('pending', 'submitted')",
             name: :fiscal_einvoice_submissions_due_index
           )

    create index(:fiscal_einvoice_submissions, [:organization_id, :status])

    create index(:fiscal_einvoice_submissions, [:organization_id, :provider_submission_id],
             where: "provider_submission_id IS NOT NULL",
             name: :fiscal_einvoice_submissions_provider_index
           )

    create constraint(:fiscal_einvoice_submissions, :fiscal_einvoice_submissions_check,
             check: """
             network IN ('peppol')
             AND status IN ('pending', 'sending', 'submitted', 'delivered', 'rejected',
                            'failed', 'uncertain')
             AND attempts >= 0 AND polls >= 0
             AND (status NOT IN ('submitted', 'delivered') OR provider_submission_id IS NOT NULL)
             """
           )

    create table(:fiscal_einvoice_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :submission_id, :binary_id, null: false
      add :attempt, :integer, null: false
      add :operation, :string, null: false
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
    ALTER TABLE fiscal_einvoice_attempts
    ADD CONSTRAINT fiscal_einvoice_attempts_submission_fkey
    FOREIGN KEY (submission_id, organization_id)
    REFERENCES fiscal_einvoice_submissions (id, organization_id) ON DELETE CASCADE
    """)

    create index(:fiscal_einvoice_attempts, [:submission_id, :started_at])

    create constraint(:fiscal_einvoice_attempts, :fiscal_einvoice_attempts_check,
             check: """
             operation IN ('submit', 'status')
             AND outcome IN ('submitted', 'delivered', 'in_progress', 'rejected', 'unauthorized',
                             'transient', 'uncertain')
             """
           )

    execute("""
    CREATE TRIGGER fiscal_einvoice_attempts_immutable
    BEFORE UPDATE OR DELETE ON fiscal_einvoice_attempts
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
