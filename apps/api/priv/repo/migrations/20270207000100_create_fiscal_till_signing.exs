defmodule Palee.Repo.Migrations.CreateFiscalTillSigning do
  @moduledoc """
  ADR-251: cash-register security (TSE in Germany, RKSV in Austria).

    * `fiscal_till_connections` – one per organization and device: the
      provider, environment, the cloud unit (TSS / signature creation
      unit) and register (client / cash register) and, outside the sandbox,
      the credentials (API key, secret and admin PIN encrypted with
      `DataCipher`, ADR-161, never returned);
    * `fiscal_till_signatures` – the outbox and the signature data of each
      receipt (and of the special RKSV receipts: start, null, monthly,
      yearly, closing). Documents stay immutable: their signature lives
      here and is printed from here;
    * `fiscal_till_signature_attempts` – insert-only log of every call.
  """

  use Ecto.Migration

  @tables ~w(fiscal_till_connections fiscal_till_signatures fiscal_till_signature_attempts)

  def up do
    create table(:fiscal_till_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :device, :string, null: false
      add :provider, :string, null: false
      add :environment, :string, null: false
      add :api_key, :binary
      add :api_secret, :binary
      add :admin_pin, :binary
      add :unit_id, :binary_id, null: false
      add :register_id, :binary_id, null: false
      add :unit_serial, :string, size: 512
      add :register_serial, :string, size: 100
      add :public_key, :text
      add :provisioned_at, :utc_datetime_usec
      add :status, :string, null: false, default: "provisioning"
      add :last_error, :string, size: 500
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fiscal_till_connections, [:organization_id, :device])

    create constraint(:fiscal_till_connections, :fiscal_till_connections_check,
             check: """
             device IN ('tse', 'rksv') AND provider IN ('sandbox', 'fiskaly')
             AND environment IN ('sandbox', 'test', 'production')
             AND status IN ('provisioning', 'active', 'invalid')
             AND (provider = 'sandbox') = (environment = 'sandbox')
             AND (environment = 'sandbox' OR (api_key IS NOT NULL AND api_secret IS NOT NULL))
             AND (status <> 'active' OR provisioned_at IS NOT NULL)
             """
           )

    create table(:fiscal_till_signatures, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :document_id, :binary_id
      add :device, :string, null: false
      add :kind, :string, null: false
      add :period, :date
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec
      add :claimed_at, :utc_datetime_usec
      add :environment, :string
      add :external_id, :binary_id, null: false
      add :transaction_number, :bigint
      add :signature_counter, :bigint
      add :signature_value, :text
      add :signature_algorithm, :string
      add :time_format, :string
      add :started_at_device, :utc_datetime_usec
      add :finished_at_device, :utc_datetime_usec
      add :unit_serial, :string, size: 512
      add :register_serial, :string, size: 100
      add :receipt_number, :string
      add :qr_code_data, :text
      add :signed_at, :utc_datetime_usec
      add :failed_at, :utc_datetime_usec
      add :last_error_code, :string, size: 60
      add :last_error_message, :string, size: 1000
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE fiscal_till_signatures
    ADD CONSTRAINT fiscal_till_signatures_document_fkey
    FOREIGN KEY (document_id, organization_id)
    REFERENCES fiscal_documents (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:fiscal_till_signatures, [:id, :organization_id],
             name: :fiscal_till_signatures_id_organization_index
           )

    create unique_index(:fiscal_till_signatures, [:document_id, :device],
             where: "document_id IS NOT NULL",
             name: :fiscal_till_signatures_document_index
           )

    create unique_index(:fiscal_till_signatures, [:organization_id, :device, :kind, :period],
             where: "kind IN ('start', 'monthly', 'yearly', 'closing')",
             name: :fiscal_till_signatures_special_index
           )

    create unique_index(:fiscal_till_signatures, [:external_id])

    create index(:fiscal_till_signatures, [:next_attempt_at],
             where: "status IN ('pending', 'uncertain')",
             name: :fiscal_till_signatures_due_index
           )

    create index(:fiscal_till_signatures, [:organization_id, :status])

    create constraint(:fiscal_till_signatures, :fiscal_till_signatures_check,
             check: """
             device IN ('tse', 'rksv')
             AND kind IN ('receipt', 'start', 'null', 'monthly', 'yearly', 'closing')
             AND status IN ('pending', 'sending', 'signed', 'uncertain', 'device_failed',
                            'rejected', 'failed')
             AND attempts >= 0
             AND (kind = 'receipt') = (document_id IS NOT NULL)
             AND (kind <> 'receipt' OR period IS NULL)
             AND (status <> 'signed' OR signature_value IS NOT NULL)
             AND (status <> 'device_failed' OR failed_at IS NOT NULL)
             """
           )

    create table(:fiscal_till_signature_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :signature_id, :binary_id, null: false
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
    ALTER TABLE fiscal_till_signature_attempts
    ADD CONSTRAINT fiscal_till_signature_attempts_signature_fkey
    FOREIGN KEY (signature_id, organization_id)
    REFERENCES fiscal_till_signatures (id, organization_id) ON DELETE CASCADE
    """)

    create index(:fiscal_till_signature_attempts, [:signature_id, :started_at])

    create constraint(:fiscal_till_signature_attempts, :fiscal_till_signature_attempts_check,
             check: """
             operation IN ('sign', 'lookup')
             AND outcome IN ('signed', 'not_found', 'rejected', 'unauthorized', 'transient',
                             'uncertain', 'device_failed')
             """
           )

    execute("""
    CREATE TRIGGER fiscal_till_signature_attempts_immutable
    BEFORE UPDATE OR DELETE ON fiscal_till_signature_attempts
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
