defmodule Palee.Repo.Migrations.CreateDocuments do
  @moduledoc """
  ADR-252: documents and signatures (V3-M8, CP-B1).

    * `document_templates` – a box's documents (waiver, terms, privacy,
      health declaration, other), each `mandatory` or `optional`;
    * `document_versions` – the immutable text of each published version,
      with its SHA-256 and whether it asks for a new signature (`major`);
    * `document_signature_requests` – a request to one person (bulk sends
      share a `batch_id`);
    * `document_signatures` – insert-only simple electronic signatures with
      their evidence (hash of the exact text, time, IP, user agent, account,
      typed name and/or drawn strokes) and the stored PDF certificate;
    * `document_audit_events` – insert-only log of publishing, requirement
      and settings changes, and of every look at health certificates;
    * `health_certificates` – only the dates and the uploaded file (GDPR
      art. 9 minimisation);
    * `document_settings` – the box's booking gate and health certificate
      rules.

  Every table is a tenant table: forced RLS on `app.organization_id` and the
  `palee_apply_tenant_context` trigger. Versions, signatures and audit events
  refuse UPDATE and DELETE, except a DELETE during the tenant purge (the
  transaction-local `palee.documents_purge` flag).
  """

  use Ecto.Migration

  @tables ~w(document_settings document_templates document_versions document_signature_requests
             document_signatures document_audit_events health_certificates)
  @immutable ~w(document_versions document_signatures document_audit_events)
  @notification_types ~w(document_signature_requested health_certificate_expiring)

  def up do
    create table(:document_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :block_booking_on_unsigned, :boolean, null: false, default: true
      add :health_certificate_required, :boolean, null: false, default: false
      add :block_booking_on_health_certificate, :boolean, null: false, default: false
      add :health_certificate_validity_months, :integer, null: false, default: 12
      add :health_certificate_reminder_days, :integer, null: false, default: 30
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:document_settings, [:organization_id])

    create constraint(:document_settings, :document_settings_check,
             check: """
             health_certificate_validity_months BETWEEN 1 AND 24
             AND health_certificate_reminder_days BETWEEN 0 AND 90
             """
           )

    create table(:document_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :kind, :string, null: false
      add :title, :string, null: false, size: 200
      add :requirement, :string, null: false, default: "optional"
      add :status, :string, null: false, default: "active"
      add :current_version_id, :binary_id
      add :current_version_number, :integer, null: false, default: 0
      # The latest `major` version: signatures of older versions no longer count.
      add :required_version_number, :integer, null: false, default: 0
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:document_templates, [:id, :organization_id],
             name: :document_templates_id_organization_index
           )

    create index(:document_templates, [:organization_id, :status])

    create constraint(:document_templates, :document_templates_check,
             check: """
             kind IN ('waiver', 'terms', 'privacy', 'health_certificate', 'other')
             AND requirement IN ('mandatory', 'optional')
             AND status IN ('active', 'archived')
             AND current_version_number >= 0
             AND required_version_number BETWEEN 0 AND current_version_number
             """
           )

    create table(:document_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :template_id, :binary_id, null: false
      add :number, :integer, null: false
      add :title, :string, null: false, size: 200
      add :body, :text, null: false
      add :language, :string, null: false, size: 10
      add :change_kind, :string, null: false
      add :content_hash, :string, null: false, size: 64
      add :published_by_id, :binary_id
      add :published_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE document_versions
    ADD CONSTRAINT document_versions_template_fkey
    FOREIGN KEY (template_id, organization_id)
    REFERENCES document_templates (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:document_versions, [:template_id, :number])

    create unique_index(:document_versions, [:id, :organization_id],
             name: :document_versions_id_organization_index
           )

    create constraint(:document_versions, :document_versions_check,
             check: """
             number >= 1 AND change_kind IN ('major', 'minor')
             AND (number > 1 OR change_kind = 'major')
             AND char_length(body) BETWEEN 1 AND 100000
             AND content_hash ~ '^[0-9a-f]{64}$'
             """
           )

    create table(:document_signature_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :template_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :batch_id, :binary_id
      add :audience, :string, null: false, default: "person"
      add :status, :string, null: false, default: "pending"
      add :requested_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :requested_at, :utc_datetime_usec, null: false
      add :signature_id, :binary_id
      add :closed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE document_signature_requests
    ADD CONSTRAINT document_signature_requests_template_fkey
    FOREIGN KEY (template_id, organization_id)
    REFERENCES document_templates (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:document_signature_requests, [:template_id, :user_id],
             where: "status = 'pending'",
             name: :document_signature_requests_pending_index
           )

    create index(:document_signature_requests, [:organization_id, :user_id, :status])
    create index(:document_signature_requests, [:organization_id, :batch_id])

    create constraint(:document_signature_requests, :document_signature_requests_check,
             check: """
             status IN ('pending', 'signed', 'cancelled')
             AND audience IN ('person', 'all_clients', 'role', 'package')
             AND (status <> 'signed' OR signature_id IS NOT NULL)
             """
           )

    # Evidence outlives the account it names: user ids are plain columns (an
    # immutable row cannot be nilified when an account is deleted).
    create table(:document_signatures, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :template_id, :binary_id, null: false
      add :version_id, :binary_id, null: false
      add :version_number, :integer, null: false
      add :request_id, :binary_id
      add :user_id, :binary_id, null: false
      add :signed_at, :utc_datetime_usec, null: false
      add :level, :string, null: false, default: "simple"
      add :provider, :string, null: false, default: "palee"
      add :content_hash, :string, null: false, size: 64
      add :typed_name, :string, size: 120
      add :drawn_signature, :map
      add :ip_address, :string, size: 64
      add :user_agent, :string, size: 512
      add :account, :map, null: false
      add :evidence_hash, :string, null: false, size: 64
      add :evidence_object_key, :string, null: false, size: 500
      add :evidence_sha256, :string, null: false, size: 64
      add :evidence_byte_size, :integer, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE document_signatures
    ADD CONSTRAINT document_signatures_version_fkey
    FOREIGN KEY (version_id, organization_id)
    REFERENCES document_versions (id, organization_id) ON DELETE CASCADE
    """)

    create index(:document_signatures, [:organization_id, :user_id, :template_id, :version_number])
    create index(:document_signatures, [:organization_id, :template_id, :signed_at])

    create constraint(:document_signatures, :document_signatures_check,
             check: """
             level IN ('simple', 'advanced', 'qualified')
             AND (typed_name IS NOT NULL OR drawn_signature IS NOT NULL)
             AND content_hash ~ '^[0-9a-f]{64}$'
             AND evidence_hash ~ '^[0-9a-f]{64}$'
             AND evidence_sha256 ~ '^[0-9a-f]{64}$'
             AND evidence_byte_size > 0
             """
           )

    create table(:document_audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :action, :string, null: false, size: 60
      add :actor_id, :binary_id
      add :subject_type, :string, null: false, size: 40
      add :subject_id, :binary_id
      add :subject_user_id, :binary_id
      add :details, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:document_audit_events, [:organization_id, :occurred_at])
    create index(:document_audit_events, [:organization_id, :subject_id])

    create table(:health_certificates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :issued_on, :date, null: false
      add :expires_on, :date, null: false
      add :file_key, :string, null: false, size: 500
      add :content_type, :string, null: false, size: 60
      add :byte_size, :integer, null: false
      add :uploaded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reminded_for, :date
      timestamps(type: :utc_datetime_usec)
    end

    create index(:health_certificates, [:organization_id, :user_id, :expires_on])
    create index(:health_certificates, [:organization_id, :expires_on])
    create unique_index(:health_certificates, [:file_key])

    create constraint(:health_certificates, :health_certificates_check,
             check: """
             expires_on > issued_on AND byte_size > 0
             AND content_type IN ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')
             """
           )

    execute("""
    CREATE OR REPLACE FUNCTION palee_documents_immutable() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'DELETE' AND current_setting('palee.documents_purge', true) = 'on' THEN
        RETURN OLD;
      END IF;
      RAISE EXCEPTION '% is insert-only (ADR-252)', TG_TABLE_NAME
        USING ERRCODE = 'insufficient_privilege';
    END;
    $$ LANGUAGE plpgsql SET search_path = pg_catalog, public
    """)

    for table <- @immutable do
      execute("""
      CREATE TRIGGER #{table}_immutable
      BEFORE UPDATE OR DELETE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION palee_documents_immutable()
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

    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))
    execute("DROP FUNCTION IF EXISTS palee_documents_immutable()")
  end

  # The same read-modify-write of notifications_type_check as earlier
  # milestones: read the current list instead of restating it.
  defp add_notification_types(types), do: rewrite_notification_types(&Enum.uniq(&1 ++ types))
  defp remove_notification_types(types), do: rewrite_notification_types(&(&1 -- types))

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = ~r/'([a-z0-9_]+)'/ |> Regex.scan(definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{in_list(change.(current))}))"
    )
  end

  defp in_list(types), do: Enum.map_join(types, ", ", &"'#{&1}'")
end
