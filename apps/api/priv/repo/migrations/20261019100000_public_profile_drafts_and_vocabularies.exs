defmodule Palee.Repo.Migrations.PublicProfileDraftsAndVocabularies do
  use Ecto.Migration

  # Board 3/3b (plan §5a): the owner edits a draft and publishes a snapshot;
  # a separate cover photo; amenities and services lists; audiences renamed
  # to their canonical keys; owners can suggest missing tags for review.
  def up do
    alter table(:organization_public_profiles) do
      add :amenities, {:array, :string}, null: false, default: []
      add :services, {:array, :string}, null: false, default: []
      add :cover_photo_id, :binary_id
      add :published_snapshot, :map
    end

    execute("""
    UPDATE organization_public_profiles
    SET audiences = array_replace(array_replace(audiences, 'women', 'women_only'), 'prenatal', 'prenatal_postnatal')
    """)

    execute("""
    UPDATE organization_public_profiles
    SET audiences = CASE WHEN 'kids' = ANY(audiences) THEN audiences ELSE audiences || ARRAY['kids']::varchar[] END,
        disciplines = array_remove(disciplines, 'kids')
    WHERE 'kids' = ANY(disciplines)
    """)

    # Profiles already live keep showing what they showed.
    execute("""
    UPDATE organization_public_profiles
    SET published_snapshot = jsonb_build_object(
      'about', about, 'disciplines', to_jsonb(disciplines), 'audiences', to_jsonb(audiences),
      'amenities', '[]'::jsonb, 'services', '[]'::jsonb, 'languages', to_jsonb(languages),
      'cover_photo_id', NULL, 'photo_ids', to_jsonb(photo_ids))
    WHERE published_at IS NOT NULL
    """)

    drop constraint(:class_types, :class_types_audiences_check)

    execute("""
    UPDATE class_types
    SET audiences = array_replace(array_replace(audiences, 'women', 'women_only'), 'prenatal', 'prenatal_postnatal')
    """)

    create constraint(:class_types, :class_types_audiences_check,
             check:
               "audiences <@ ARRAY['women_only', 'teens', 'kids', 'over_40', 'seniors', 'prenatal_postnatal', 'adaptive']::text[]"
           )

    create table(:profile_tag_suggestions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :suggested_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :list, :text, null: false
      add :name, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :resolved_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:profile_tag_suggestions, :profile_tag_suggestions_list_check,
             check: "list IN ('disciplines', 'audiences', 'amenities', 'services')"
           )

    create constraint(:profile_tag_suggestions, :profile_tag_suggestions_name_check,
             check: "char_length(name) BETWEEN 2 AND 60"
           )

    create constraint(:profile_tag_suggestions, :profile_tag_suggestions_status_check,
             check: "status IN ('pending', 'added', 'declined')"
           )

    create index(:profile_tag_suggestions, [:organization_id, :inserted_at])
    create index(:profile_tag_suggestions, [:status, :inserted_at])

    execute("""
    CREATE TRIGGER profile_tag_suggestions_apply_tenant_context
    BEFORE INSERT OR UPDATE ON profile_tag_suggestions
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY profile_tag_suggestions_tenant_policy ON profile_tag_suggestions
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE profile_tag_suggestions ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE profile_tag_suggestions FORCE ROW LEVEL SECURITY")

    # The platform reviews suggestions from every gym; these functions are the
    # only cross-tenant path, and return only what review needs.
    execute("""
    CREATE FUNCTION palee_pending_tag_suggestions()
    RETURNS TABLE (id uuid, organization_name text, list text, name text, inserted_at timestamp)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
      SELECT s.id, o.name::text, s.list, s.name, s.inserted_at::timestamp
      FROM profile_tag_suggestions s JOIN organizations o ON o.id = s.organization_id
      WHERE s.status = 'pending'
      ORDER BY s.inserted_at
      LIMIT 500
    $$
    """)

    execute("""
    CREATE FUNCTION palee_resolve_tag_suggestion(suggestion_id uuid, new_status text)
    RETURNS integer
    LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = public AS $$
      WITH changed AS (
        UPDATE profile_tag_suggestions
        SET status = new_status, resolved_at = now(), updated_at = now()
        WHERE id = suggestion_id AND status = 'pending' AND new_status IN ('added', 'declined')
        RETURNING 1
      )
      SELECT count(*)::integer FROM changed
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_resolve_tag_suggestion(uuid, text)")
    execute("DROP FUNCTION IF EXISTS palee_pending_tag_suggestions()")
    drop table(:profile_tag_suggestions)
    drop constraint(:class_types, :class_types_audiences_check)

    execute("""
    UPDATE class_types
    SET audiences = array_replace(array_replace(audiences, 'women_only', 'women'), 'prenatal_postnatal', 'prenatal')
    """)

    create constraint(:class_types, :class_types_audiences_check,
             check:
               "audiences <@ ARRAY['women', 'teens', 'kids', 'over_40', 'seniors', 'prenatal', 'adaptive']::text[]"
           )

    alter table(:organization_public_profiles) do
      remove :published_snapshot
      remove :cover_photo_id
      remove :services
      remove :amenities
    end
  end
end
