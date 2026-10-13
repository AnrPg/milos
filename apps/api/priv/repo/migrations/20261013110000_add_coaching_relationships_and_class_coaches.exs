defmodule MilosTraining.Repo.Migrations.AddCoachingRelationshipsAndClassCoaches do
  use Ecto.Migration

  # ADR-100: coaches are linked to their clients and to the classes they
  # coach; a coach's client invitation carries the coach.
  def up do
    create table(:coaching_relationships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :coach_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :client_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :origin, :string, null: false
      add :started_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec
      add :ended_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :coaching_relationships,
             [:organization_id, :coach_user_id, :client_user_id],
             where: "ended_at IS NULL",
             name: :coaching_relationships_active_index
           )

    create index(:coaching_relationships, [:organization_id, :client_user_id])

    create constraint(:coaching_relationships, :coaching_relationships_origin,
             check: "origin IN ('assigned', 'self_assigned', 'invited')"
           )

    create constraint(:coaching_relationships, :coaching_relationships_distinct_people,
             check: "coach_user_id <> client_user_id"
           )

    execute("""
    CREATE TRIGGER coaching_relationships_apply_tenant_context
    BEFORE INSERT OR UPDATE ON coaching_relationships
    FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY coaching_relationships_tenant_policy ON coaching_relationships
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE coaching_relationships ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE coaching_relationships FORCE ROW LEVEL SECURITY")

    alter table(:class_series) do
      add :coach_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:scheduled_classes) do
      add :coach_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:scheduled_classes, [:organization_id, :coach_user_id],
             where: "coach_user_id IS NOT NULL"
           )

    alter table(:registration_invitations) do
      add :coach_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end
  end

  def down do
    alter table(:registration_invitations) do
      remove :coach_user_id
    end

    drop index(:scheduled_classes, [:organization_id, :coach_user_id])

    alter table(:scheduled_classes) do
      remove :coach_user_id
    end

    alter table(:class_series) do
      remove :coach_user_id
    end

    drop table(:coaching_relationships)
  end
end
