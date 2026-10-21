defmodule Palee.Repo.Migrations.MediaAndPublicProfiles do
  @moduledoc """
  ADR-148: uploaded images, one table per ownership scope so each carries one
  RLS rule and one deletion rule:

  - `media_tenant_objects` belong to a gym (box photos, post photos) and stay
    when the uploader leaves;
  - `media_account_objects` belong to a person (body photos) and go with the
    account.

  ADR-142: a gym's public profile (Σχετικά of the public box page). Public
  read access for logged-out visitors arrives with the public box page.
  """

  use Ecto.Migration

  def change do
    create table(:media_tenant_objects, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :uploaded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :purpose, :string, null: false
      add :object_key, :text, null: false
      add :content_type, :string, null: false
      add :byte_size, :integer
      add :width, :integer
      add :height, :integer
      add :status, :string, null: false, default: "pending"
      add :attached_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:media_tenant_objects, [:object_key])
    create unique_index(:media_tenant_objects, [:id, :organization_id])
    create index(:media_tenant_objects, [:organization_id, :status, :attached_at])

    create constraint(:media_tenant_objects, :media_tenant_objects_purpose_check,
             check: "purpose IN ('box_photo', 'post_photo')"
           )

    create constraint(:media_tenant_objects, :media_tenant_objects_status_check,
             check: "status IN ('pending', 'ready')"
           )

    enable_tenant_rls("media_tenant_objects")

    create table(:media_account_objects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :purpose, :string, null: false
      add :object_key, :text, null: false
      add :content_type, :string, null: false
      add :byte_size, :integer
      add :width, :integer
      add :height, :integer
      add :status, :string, null: false, default: "pending"
      add :attached_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:media_account_objects, [:object_key])
    create index(:media_account_objects, [:user_id, :status, :attached_at])

    create constraint(:media_account_objects, :media_account_objects_purpose_check,
             check: "purpose IN ('body_photo')"
           )

    create constraint(:media_account_objects, :media_account_objects_status_check,
             check: "status IN ('pending', 'ready')"
           )

    execute(
      """
      CREATE POLICY media_account_objects_owner_policy ON media_account_objects
      USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS media_account_objects_owner_policy ON media_account_objects"
    )

    execute(
      "ALTER TABLE media_account_objects ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE media_account_objects DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE media_account_objects FORCE ROW LEVEL SECURITY",
      "ALTER TABLE media_account_objects NO FORCE ROW LEVEL SECURITY"
    )

    # The orphan sweep runs outside any person's session; this answers only
    # which people have unattached uploads older than the cutoff (ADR-131).
    execute(
      """
      CREATE FUNCTION palee_account_media_orphan_owner_ids(cutoff timestamp)
      RETURNS SETOF uuid
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
      AS $$
        SELECT DISTINCT user_id FROM media_account_objects
        WHERE attached_at IS NULL AND inserted_at < cutoff
      $$
      """,
      "DROP FUNCTION IF EXISTS palee_account_media_orphan_owner_ids(timestamp)"
    )

    create table(:organization_public_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :about, :text
      add :disciplines, {:array, :string}, null: false, default: []
      add :languages, {:array, :string}, null: false, default: []
      add :audiences, {:array, :string}, null: false, default: []
      add :photo_ids, {:array, :binary_id}, null: false, default: []
      add :published_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_public_profiles, [:organization_id])

    create constraint(:organization_public_profiles, :organization_public_profiles_about_check,
             check: "about IS NULL OR char_length(about) <= 2000"
           )

    create constraint(:organization_public_profiles, :organization_public_profiles_photos_check,
             check: "cardinality(photo_ids) <= 12"
           )

    enable_tenant_rls("organization_public_profiles")
  end

  defp enable_tenant_rls(table) do
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
