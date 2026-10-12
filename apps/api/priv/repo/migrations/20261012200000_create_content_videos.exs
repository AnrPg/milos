defmodule MilosTraining.Repo.Migrations.CreateContentVideos do
  use Ecto.Migration

  # ADR-098: on-demand video items, linked from an external host.

  def up do
    create table(:content_videos, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :title, :string, null: false
      add :description, :text
      add :video_url, :text, null: false
      add :duration_minutes, :integer
      add :tags, {:array, :string}, null: false, default: []
      add :published_at, :utc_datetime_usec
      add :archived_at, :utc_datetime_usec
      add :created_by_id, :binary_id

      timestamps(type: :utc_datetime_usec)
    end

    create index(:content_videos, [:organization_id, :published_at])

    execute("""
    CREATE TRIGGER content_videos_apply_tenant_context
    BEFORE INSERT OR UPDATE ON content_videos
    FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY content_videos_tenant_policy ON content_videos
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE content_videos ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE content_videos FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:content_videos)
  end
end
