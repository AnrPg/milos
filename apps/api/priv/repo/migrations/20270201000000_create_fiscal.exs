defmodule Palee.Repo.Migrations.CreateFiscal do
  @moduledoc """
  ADR-240–242: the Fiscal context. A business's legal identity, gapless
  document series, insert-only fiscal documents and lines, the hash-chained
  journal with its head pointer, and period closings.

  Documents, lines, journal entries and closings reject every UPDATE and
  every DELETE except a tenant purge after the retention period, which sets
  `palee.fiscal_purge = 'on'` for its own transaction.

  Every table is tenant scoped (forced RLS, `palee_apply_tenant_context`)
  with composite `(id, organization_id)` foreign keys, like ADR-104.
  """

  use Ecto.Migration

  @tables ~w(fiscal_business_identities fiscal_sequences fiscal_documents
             fiscal_document_lines fiscal_journal_heads fiscal_journal_entries
             fiscal_period_closings)

  @immutable ~w(fiscal_documents fiscal_document_lines fiscal_journal_entries
                fiscal_period_closings)

  def up do
    create table(:fiscal_business_identities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :legal_name, :string
      add :trade_name, :string
      add :country_code, :string, size: 2, null: false
      add :tax_id, :string
      add :vat_number, :string
      add :tax_office, :string
      add :registration_number, :string
      add :activity_code, :string
      add :vat_scheme, :string, null: false, default: "standard"
      add :street, :string
      add :building_number, :string
      add :postal_code, :string
      add :city, :string
      add :region, :string
      add :email, :string
      add :phone, :string
      add :document_language, :string
      add :currency, :string, size: 3, null: false
      add :branch_code, :integer, null: false, default: 0
      add :fiscal_year_start_month, :integer, null: false, default: 1
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fiscal_business_identities, [:organization_id])

    create constraint(:fiscal_business_identities, :fiscal_business_identities_scheme_check,
             check: "vat_scheme IN ('standard', 'small_business', 'exempt')"
           )

    create constraint(:fiscal_business_identities, :fiscal_business_identities_branch_check,
             check: "branch_code BETWEEN 0 AND 9999 AND fiscal_year_start_month BETWEEN 1 AND 12"
           )

    create table(:fiscal_sequences, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :series, :string, null: false
      add :last_value, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fiscal_sequences, [:organization_id, :series])

    create constraint(:fiscal_sequences, :fiscal_sequences_value_check, check: "last_value >= 0")

    create table(:fiscal_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :kind, :string, null: false
      add :series, :string, null: false
      add :sequence, :bigint, null: false
      add :number, :string, null: false
      add :issue_date, :date, null: false
      add :issued_at, :utc_datetime_usec, null: false
      add :currency, :string, size: 3, null: false
      add :prices_include_tax, :boolean, null: false
      add :country_code, :string, size: 2, null: false
      add :language, :string, null: false
      add :seller, :map, null: false
      add :buyer, :map
      add :payment_method, :string
      add :net_cents, :bigint, null: false
      add :tax_cents, :bigint, null: false
      add :gross_cents, :bigint, null: false
      add :tax_breakdown, {:array, :map}, null: false, default: []
      add :corrects_document_id, :binary_id
      add :source_type, :string
      add :source_id, :binary_id
      add :idempotency_key, :string
      add :request_hash, :string
      add :content_hash, :string, null: false
      add :journal_position, :bigint, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:fiscal_documents, [:id, :organization_id],
             name: :fiscal_documents_id_organization_index
           )

    create unique_index(:fiscal_documents, [:organization_id, :series, :sequence])
    create unique_index(:fiscal_documents, [:organization_id, :number])

    create unique_index(:fiscal_documents, [:organization_id, :idempotency_key],
             where: "idempotency_key IS NOT NULL",
             name: :fiscal_documents_idempotency_index
           )

    create index(:fiscal_documents, [:organization_id, :issue_date])

    create index(:fiscal_documents, [:corrects_document_id],
             where: "corrects_document_id IS NOT NULL"
           )

    create index(:fiscal_documents, [:organization_id, :source_type, :source_id])

    execute("""
    ALTER TABLE fiscal_documents
    ADD CONSTRAINT fiscal_documents_corrects_fkey
    FOREIGN KEY (corrects_document_id, organization_id)
    REFERENCES fiscal_documents (id, organization_id)
    """)

    create constraint(:fiscal_documents, :fiscal_documents_kind_check,
             check: "kind IN ('receipt', 'invoice', 'credit_note')"
           )

    create constraint(:fiscal_documents, :fiscal_documents_credit_check,
             check: "(kind = 'credit_note') = (corrects_document_id IS NOT NULL)"
           )

    create constraint(:fiscal_documents, :fiscal_documents_amounts_check,
             check:
               "sequence > 0 AND net_cents >= 0 AND tax_cents >= 0 AND gross_cents = net_cents + tax_cents"
           )

    create constraint(:fiscal_documents, :fiscal_documents_currency_check,
             check: "currency IN ('EUR', 'CHF', 'GBP', 'USD')"
           )

    create table(:fiscal_document_lines, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :document_id, :binary_id, null: false
      add :position, :integer, null: false
      add :description, :string, size: 300, null: false
      add :quantity, :integer, null: false
      add :unit_price_cents, :bigint, null: false
      add :discount_cents, :bigint, null: false, default: 0
      add :amount_cents, :bigint, null: false
      add :tax_category, :string, null: false
      add :rate_bp, :integer, null: false
      add :exemption_reason, :string, size: 300
      add :net_cents, :bigint, null: false
      add :tax_cents, :bigint, null: false
      add :gross_cents, :bigint, null: false
      add :corrects_position, :integer
      add :source_type, :string
      add :source_id, :binary_id
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE fiscal_document_lines
    ADD CONSTRAINT fiscal_document_lines_document_fkey
    FOREIGN KEY (document_id, organization_id)
    REFERENCES fiscal_documents (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:fiscal_document_lines, [:document_id, :position])

    create constraint(:fiscal_document_lines, :fiscal_document_lines_amounts_check,
             check: """
             position > 0 AND quantity > 0 AND unit_price_cents >= 0 AND discount_cents >= 0
             AND amount_cents = quantity * unit_price_cents - discount_cents
             AND rate_bp BETWEEN 0 AND 9999 AND net_cents >= 0 AND tax_cents >= 0
             AND gross_cents = net_cents + tax_cents
             """
           )

    create constraint(:fiscal_document_lines, :fiscal_document_lines_exempt_check,
             check: "tax_category <> 'exempt' OR exemption_reason IS NOT NULL"
           )

    create table(:fiscal_journal_heads, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :bigint, null: false, default: 0
      add :hash, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fiscal_journal_heads, [:organization_id])

    create table(:fiscal_journal_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :bigint, null: false
      add :event_type, :string, null: false
      add :subject_type, :string
      add :subject_id, :binary_id
      add :actor_id, :binary_id
      add :occurred_at, :utc_datetime_usec, null: false
      add :payload, :map, null: false
      add :previous_hash, :string, null: false
      add :hash, :string, null: false
      add :signature, :text, null: false
      add :signature_key_id, :string, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:fiscal_journal_entries, [:organization_id, :position])
    create index(:fiscal_journal_entries, [:organization_id, :occurred_at])

    create constraint(:fiscal_journal_entries, :fiscal_journal_entries_position_check,
             check: "position > 0 AND length(hash) = 64 AND length(previous_hash) = 64"
           )

    create table(:fiscal_period_closings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :period_kind, :string, null: false
      add :period_start, :date, null: false
      add :period_end, :date, null: false
      add :totals, :map, null: false
      add :journal_position, :bigint, null: false
      add :closed_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:fiscal_period_closings, [:organization_id, :period_kind, :period_start])

    create constraint(:fiscal_period_closings, :fiscal_period_closings_kind_check,
             check: "period_kind IN ('day', 'month', 'year') AND period_end >= period_start"
           )

    execute("""
    CREATE OR REPLACE FUNCTION palee_fiscal_immutable() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'DELETE' AND current_setting('palee.fiscal_purge', true) = 'on' THEN
        RETURN OLD;
      END IF;
      RAISE EXCEPTION '% is insert-only (ADR-241/242)', TG_TABLE_NAME
        USING ERRCODE = 'insufficient_privilege';
    END;
    $$ LANGUAGE plpgsql SET search_path = pg_catalog, public
    """)

    for table <- @immutable do
      execute("""
      CREATE TRIGGER #{table}_immutable
      BEFORE UPDATE OR DELETE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION palee_fiscal_immutable()
      """)
    end

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
    execute("DROP FUNCTION IF EXISTS palee_fiscal_immutable()")
  end
end
