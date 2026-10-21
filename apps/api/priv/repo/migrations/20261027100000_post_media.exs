defmodule Palee.Repo.Migrations.PostMedia do
  use Ecto.Migration

  # ADR-157 (P2-M9): photos and short videos in posts.
  #
  # - Post media belong to the person who uploaded them (media_account_objects,
  #   purposes post_photo and post_video): they follow the author, go with the
  #   account, and a compose can change its destination without re-uploading.
  #   `post_photo` leaves the gym-owned table, which never held one.
  # - The server processes post media: pending → processing → ready | rejected.
  #   `variants` keeps the generated renditions ({name: {key, content_type,
  #   width, height, bytes}}), `placeholder` a tiny blurred data URI,
  #   `duration_ms` a video's length, `alt_text` the author's description.
  # - `attached_type`/`attached_id` name the consumer an upload belongs to
  #   (`community_post`, `profile_post`), `attached_organization_id` the gym
  #   that runs a club post, so processing can refresh that post.
  # - Posts keep an ordered snapshot of their media (`media`, up to ten
  #   photos or one video) and whether they are ready to show
  #   (`media_status`). Only the author sees a post that is not `ready`.
  # - Daily, uploads attached to a post that no longer exists are released,
  #   and attached uploads stuck before `ready` are rejected; those lookups
  #   cross people and gyms, so they are narrow SECURITY DEFINER functions
  #   that answer only owner and media ids.

  @statuses_before "status IN ('pending', 'ready')"
  @statuses "status IN ('pending', 'processing', 'ready', 'rejected')"
  @post_media_statuses ~w(ready processing failed)

  def up do
    for table <- ~w(media_account_objects media_tenant_objects)a do
      alter table(table) do
        add :variants, :map, null: false, default: %{}
        add :placeholder, :text
        add :alt_text, :text
        add :duration_ms, :integer
        add :rejection_reason, :string
        add :attached_type, :string
        add :attached_id, :binary_id
        add :attached_organization_id, :binary_id
      end

      execute("ALTER TABLE #{table} DROP CONSTRAINT #{table}_status_check")
      create constraint(table, :"#{table}_status_check", check: @statuses)

      create constraint(table, :"#{table}_alt_text_check",
               check: "alt_text IS NULL OR char_length(alt_text) <= 500"
             )

      create constraint(table, :"#{table}_attached_check",
               check:
                 "(attached_type IS NULL AND attached_id IS NULL) OR " <>
                   "(attached_type IN ('community_post', 'profile_post') AND attached_id IS NOT NULL)"
             )

      create index(table, [:attached_type, :attached_id], where: "attached_id IS NOT NULL")
    end

    execute(
      "ALTER TABLE media_account_objects DROP CONSTRAINT media_account_objects_purpose_check"
    )

    create constraint(:media_account_objects, :media_account_objects_purpose_check,
             check: "purpose IN ('body_photo', 'post_photo', 'post_video')"
           )

    execute("ALTER TABLE media_tenant_objects DROP CONSTRAINT media_tenant_objects_purpose_check")

    create constraint(:media_tenant_objects, :media_tenant_objects_purpose_check,
             check: "purpose IN ('box_photo')"
           )

    for table <- ~w(community_posts community_profile_posts)a do
      alter table(table) do
        add :media, {:array, :map}, null: false, default: []
        add :media_status, :string, null: false, default: "ready"
      end

      create constraint(table, :"#{table}_media_check", check: "cardinality(media) <= 10")

      create constraint(table, :"#{table}_media_status_check",
               check: "media_status IN (#{quoted(@post_media_statuses)})"
             )

      execute("ALTER TABLE #{table} DROP CONSTRAINT #{table}_content_check")

      create constraint(table, :"#{table}_content_check",
               check:
                 "attachment_type IS NOT NULL OR cardinality(media) > 0 OR " <>
                   "(body IS NOT NULL AND length(btrim(body)) > 0)"
             )
    end

    execute("""
    CREATE FUNCTION palee_dangling_post_media(cutoff timestamp, max_rows integer)
    RETURNS TABLE (user_id uuid, media_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT m.user_id, m.id
      FROM media_account_objects m
      WHERE m.attached_id IS NOT NULL AND m.attached_at < cutoff
        AND NOT CASE m.attached_type
          WHEN 'community_post' THEN EXISTS (
            SELECT 1 FROM community_posts p
            WHERE p.id = m.attached_id AND p.deleted_at IS NULL)
          WHEN 'profile_post' THEN EXISTS (
            SELECT 1 FROM community_profile_posts p
            WHERE p.id = m.attached_id AND p.deleted_at IS NULL)
          ELSE true
        END
      ORDER BY m.attached_at
      LIMIT max_rows
    $$
    """)

    # Attached uploads that never became ready (the upload never finished, a
    # job was lost): the sweep rejects them so their post stops waiting.
    execute("""
    CREATE FUNCTION palee_stale_post_media(cutoff timestamp, max_rows integer)
    RETURNS TABLE (user_id uuid, media_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT m.user_id, m.id
      FROM media_account_objects m
      WHERE m.attached_id IS NOT NULL AND m.status IN ('pending', 'processing')
        AND m.updated_at < cutoff
      ORDER BY m.updated_at
      LIMIT max_rows
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_stale_post_media(timestamp, integer)")
    execute("DROP FUNCTION IF EXISTS palee_dangling_post_media(timestamp, integer)")

    for table <- ~w(community_posts community_profile_posts)a do
      execute("ALTER TABLE #{table} DROP CONSTRAINT #{table}_content_check")

      create constraint(table, :"#{table}_content_check",
               check:
                 "attachment_type IS NOT NULL OR (body IS NOT NULL AND length(btrim(body)) > 0)"
             )

      alter table(table) do
        remove :media
        remove :media_status
      end
    end

    execute("DELETE FROM media_account_objects WHERE purpose IN ('post_photo', 'post_video')")

    execute(
      "ALTER TABLE media_account_objects DROP CONSTRAINT media_account_objects_purpose_check"
    )

    create constraint(:media_account_objects, :media_account_objects_purpose_check,
             check: "purpose IN ('body_photo')"
           )

    execute("ALTER TABLE media_tenant_objects DROP CONSTRAINT media_tenant_objects_purpose_check")

    create constraint(:media_tenant_objects, :media_tenant_objects_purpose_check,
             check: "purpose IN ('box_photo', 'post_photo')"
           )

    for table <- ~w(media_account_objects media_tenant_objects)a do
      execute("DELETE FROM #{table} WHERE status IN ('processing', 'rejected')")
      execute("ALTER TABLE #{table} DROP CONSTRAINT #{table}_status_check")
      create constraint(table, :"#{table}_status_check", check: @statuses_before)
      execute("ALTER TABLE #{table} DROP CONSTRAINT #{table}_alt_text_check")
      execute("ALTER TABLE #{table} DROP CONSTRAINT #{table}_attached_check")

      alter table(table) do
        remove :variants
        remove :placeholder
        remove :alt_text
        remove :duration_ms
        remove :rejection_reason
        remove :attached_type
        remove :attached_id
        remove :attached_organization_id
      end
    end
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
