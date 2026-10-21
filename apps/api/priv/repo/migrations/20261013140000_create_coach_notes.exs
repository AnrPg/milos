defmodule Palee.Repo.Migrations.CreateCoachNotes do
  use Ecto.Migration

  # ADR-101: private coach notes about a client and every read of them by
  # someone other than their author.
  def change do
    create table(:coaching_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :coach_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :client_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :body, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:coaching_notes, [:id, :organization_id],
             name: :coaching_notes_id_organization_index
           )

    create index(:coaching_notes, [:organization_id, :client_user_id])

    create table(:coaching_note_reads, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :note_id, :binary_id, null: false

      add :reader_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :read_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute(
      """
      ALTER TABLE coaching_note_reads
      ADD CONSTRAINT coaching_note_reads_note_fkey
      FOREIGN KEY (note_id, organization_id)
      REFERENCES coaching_notes (id, organization_id) ON DELETE CASCADE
      """,
      "ALTER TABLE coaching_note_reads DROP CONSTRAINT coaching_note_reads_note_fkey"
    )

    create index(:coaching_note_reads, [:note_id, :read_at])

    for table <- ["coaching_notes", "coaching_note_reads"] do
      execute(
        """
        CREATE TRIGGER #{table}_apply_tenant_context
        BEFORE INSERT OR UPDATE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
        """,
        "DROP TRIGGER IF EXISTS #{table}_apply_tenant_context ON #{table}"
      )

      execute(
        """
        CREATE POLICY #{table}_tenant_policy ON #{table}
        USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
        WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
        """,
        "DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}"
      )

      execute(
        "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY",
        "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
      )

      execute(
        "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY",
        "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
      )
    end
  end
end
