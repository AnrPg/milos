defmodule Palee.Repo.Migrations.BodySnapshots do
  @moduledoc """
  ADR-158 (P2-M10, Σώμα): body measurement snapshots, their private photos,
  health consents, body settings and the audit of coach reads.

  Body data is the person's own (account-scoped, never a gym's): every table
  keys on `user_id`, the owner reads and writes it in any session, and it
  goes with the account.

  - `body_snapshots`: `metrics` holds canonical values in SI units (kg, cm,
    %), whatever unit the person typed. `visibility` is `private` (default),
    `coach_numbers` or `coach_full` (numbers and photos). `source` is
    `manual`, or `garmin` for a weight a connected device sends (P2-M13).
  - `body_snapshot_photos`: one row per photo, pointing at the person's
    upload (`media_account_objects`, purpose `body_photo`, private bucket).
    The row keeps the renditions' keys so a coach session, which cannot read
    the person's media rows, can be given short-lived signed URLs.
  - `user_health_consents`: one row per grant; a withdrawal closes it. Photos
    need an active `body_photos` grant.
  - `body_settings`: units, how weight shows (number, trend, hidden), which
    journal sections are on, the optional measure reminder, the last
    visibility used, whether photos show blurred until tapped and how two
    snapshots are compared (slider or side by side).
  - `body_access_log`: one row per coach read (who, whose, in which gym, what
    was shown). The member reads their own rows; the gym's rows are purged
    with the gym, like `journal_coach_reads`.

  A coach of a gym reads a member's shared snapshots only while the member
  is active there (`palee_body_visible_to_acting_coach`), and their photos
  only on `coach_full` with an active consent (`palee_body_photos_consented`).
  Both are narrow SECURITY DEFINER functions answering one boolean.

  Body photos attach to their snapshot (`attached_type = 'body_snapshot'`),
  so the daily dangling-media sweep learns that kind, and a member's due
  measure reminders are found through a definer lookup that answers ids only.
  """

  use Ecto.Migration

  @visibilities "('private', 'coach_numbers', 'coach_full')"
  @notification_types ~w(body_measure_reminder)

  def up do
    create table(:body_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :taken_at, :utc_datetime_usec, null: false
      add :taken_tz, :string, null: false, default: "UTC"
      add :metrics, :map, null: false, default: %{}
      add :notes, :text
      add :visibility, :string, null: false, default: "private"
      add :source, :string, null: false, default: "manual"

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:body_snapshots, :body_snapshots_source_check,
             check: "source IN ('manual', 'garmin')"
           )

    create constraint(:body_snapshots, :body_snapshots_visibility_check,
             check: "visibility IN #{@visibilities}"
           )

    create constraint(:body_snapshots, :body_snapshots_notes_check,
             check: "notes IS NULL OR char_length(notes) <= 2000"
           )

    create constraint(:body_snapshots, :body_snapshots_metrics_check,
             check: "jsonb_typeof(metrics) = 'object'"
           )

    create index(:body_snapshots, [:user_id, :taken_at, :id])

    create table(:body_snapshot_photos, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :snapshot_id, references(:body_snapshots, type: :binary_id, on_delete: :delete_all),
        null: false

      add :media_id,
          references(:media_account_objects, type: :binary_id, on_delete: :delete_all),
          null: false

      add :pose, :string, null: false
      add :status, :string, null: false, default: "processing"
      add :variants, :map, null: false, default: %{}
      add :width, :integer
      add :height, :integer
      add :placeholder, :text

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:body_snapshot_photos, :body_snapshot_photos_pose_check,
             check: "pose IN ('front', 'side', 'back', 'other')"
           )

    create constraint(:body_snapshot_photos, :body_snapshot_photos_status_check,
             check: "status IN ('processing', 'ready', 'failed')"
           )

    create unique_index(:body_snapshot_photos, [:media_id])
    create index(:body_snapshot_photos, [:snapshot_id])
    create index(:body_snapshot_photos, [:user_id, :pose])

    create table(:user_health_consents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :scope, :string, null: false
      add :granted_at, :utc_datetime_usec, null: false
      add :withdrawn_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:user_health_consents, :user_health_consents_scope_check,
             check: "scope IN ('body_photos', 'health_data')"
           )

    create unique_index(:user_health_consents, [:user_id, :scope],
             where: "withdrawn_at IS NULL",
             name: :user_health_consents_active_index
           )

    create table(:body_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :units, :string, null: false, default: "metric"
      add :weight_display, :string, null: false, default: "number"

      add :journal_sections, :map,
        null: false,
        default: %{"body" => true, "wellness" => true, "cravings" => true}

      add :measure_reminder_weeks, :integer
      add :reminder_anchor_at, :utc_datetime_usec
      add :last_reminded_at, :utc_datetime_usec
      add :default_visibility, :string, null: false, default: "private"
      add :blur_photos, :boolean, null: false, default: true
      add :compare_mode, :string, null: false, default: "slider"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:body_settings, [:user_id])

    create constraint(:body_settings, :body_settings_units_check,
             check: "units IN ('metric', 'imperial')"
           )

    create constraint(:body_settings, :body_settings_weight_display_check,
             check: "weight_display IN ('number', 'trend', 'hidden')"
           )

    create constraint(:body_settings, :body_settings_reminder_check,
             check: "measure_reminder_weeks IS NULL OR measure_reminder_weeks BETWEEN 1 AND 12"
           )

    create constraint(:body_settings, :body_settings_default_visibility_check,
             check: "default_visibility IN #{@visibilities}"
           )

    create constraint(:body_settings, :body_settings_compare_mode_check,
             check: "compare_mode IN ('slider', 'side_by_side')"
           )

    create index(:body_settings, [:measure_reminder_weeks],
             where: "measure_reminder_weeks IS NOT NULL"
           )

    create table(:body_access_log, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :reader_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :subject, :string, null: false
      add :snapshot_ids, {:array, :binary_id}, null: false, default: []
      add :photos_shown, :boolean, null: false, default: false
      add :read_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:body_access_log, :body_access_log_subject_check,
             check: "subject IN ('list', 'snapshot')"
           )

    create index(:body_access_log, [:user_id, :read_at])
    create index(:body_access_log, [:organization_id, :read_at])

    functions()
    policies()

    execute(
      "ALTER TABLE media_account_objects DROP CONSTRAINT media_account_objects_attached_check"
    )

    create constraint(:media_account_objects, :media_account_objects_attached_check,
             check:
               "(attached_type IS NULL AND attached_id IS NULL) OR " <>
                 "(attached_type IN ('community_post', 'profile_post', 'body_snapshot') " <>
                 "AND attached_id IS NOT NULL)"
           )

    dangling_post_media(true)
    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)
    dangling_post_media(false)

    execute(
      "DELETE FROM media_account_objects WHERE purpose = 'body_photo' AND attached_type = 'body_snapshot'"
    )

    execute(
      "ALTER TABLE media_account_objects DROP CONSTRAINT media_account_objects_attached_check"
    )

    create constraint(:media_account_objects, :media_account_objects_attached_check,
             check:
               "(attached_type IS NULL AND attached_id IS NULL) OR " <>
                 "(attached_type IN ('community_post', 'profile_post') AND attached_id IS NOT NULL)"
           )

    drop table(:body_access_log)
    drop table(:body_settings)
    drop table(:user_health_consents)
    drop table(:body_snapshot_photos)
    drop table(:body_snapshots)

    for function <- [
          "palee_body_visible_to_acting_coach(uuid)",
          "palee_body_photos_consented(uuid)",
          "palee_body_reminders_due(timestamp, integer)"
        ] do
      execute("DROP FUNCTION IF EXISTS #{function}")
    end
  end

  defp functions do
    # Is the session user a coach of the session's gym, where the member is
    # active? One boolean about one member; the memberships it reads are
    # invisible to the coach's session.
    execute("""
    CREATE FUNCTION palee_body_visible_to_acting_coach(member_id uuid)
    RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT NULLIF(current_setting('app.organization_id', true), '') IS NOT NULL
        AND member_id IS DISTINCT FROM NULLIF(current_setting('app.user_id', true), '')::uuid
        AND public.palee_acting_user_coaches(
          NULLIF(current_setting('app.organization_id', true), '')::uuid
        )
        AND EXISTS (
          SELECT 1 FROM public.organization_memberships target
          WHERE target.organization_id =
                  NULLIF(current_setting('app.organization_id', true), '')::uuid
            AND target.user_id = member_id
            AND target.status = 'active'
        )
    $$
    """)

    # Whether the member's body-photo consent is active right now.
    execute("""
    CREATE FUNCTION palee_body_photos_consented(member_id uuid)
    RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
        SELECT 1 FROM public.user_health_consents c
        WHERE c.user_id = member_id AND c.scope = 'body_photos' AND c.withdrawn_at IS NULL
      )
    $$
    """)

    # People whose opt-in measure reminder is due: N weeks after the later of
    # their last snapshot, their last reminder and the moment they turned the
    # reminder on. Answers ids only; the job works in each person's session.
    execute("""
    CREATE FUNCTION palee_body_reminders_due(p_now timestamp, p_lim integer)
    RETURNS SETOF uuid
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT s.user_id
      FROM public.body_settings s
      WHERE s.measure_reminder_weeks IS NOT NULL
        AND GREATEST(
              s.reminder_anchor_at,
              s.last_reminded_at,
              (SELECT max(b.taken_at) FROM public.body_snapshots b WHERE b.user_id = s.user_id)
            ) + make_interval(weeks => s.measure_reminder_weeks) <= p_now
      ORDER BY s.last_reminded_at NULLS FIRST, s.user_id
      LIMIT p_lim
    $$
    """)
  end

  defp policies do
    for table <-
          ~w(body_snapshots body_snapshot_photos user_health_consents body_settings) do
      execute("""
      CREATE POLICY #{table}_owner_policy ON #{table}
      USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      """)
    end

    execute("""
    CREATE POLICY body_snapshots_coach_read_policy ON body_snapshots
    FOR SELECT
    USING (
      visibility IN ('coach_numbers', 'coach_full')
      AND palee_body_visible_to_acting_coach(user_id)
    )
    """)

    # Photos follow their snapshot (whose own policy applies inside EXISTS),
    # and only while it is shared with photos and the consent is active.
    execute("""
    CREATE POLICY body_snapshot_photos_coach_read_policy ON body_snapshot_photos
    FOR SELECT
    USING (
      EXISTS (
        SELECT 1 FROM body_snapshots s
        WHERE s.id = snapshot_id AND s.visibility = 'coach_full'
      )
      AND palee_body_photos_consented(user_id)
      AND palee_body_visible_to_acting_coach(user_id)
    )
    """)

    # A coach sees the member's display choice (and units), nothing else.
    execute("""
    CREATE POLICY body_settings_coach_read_policy ON body_settings
    FOR SELECT
    USING (palee_body_visible_to_acting_coach(user_id))
    """)

    execute("""
    CREATE TRIGGER body_access_log_apply_tenant_context
    BEFORE INSERT OR UPDATE ON body_access_log
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY body_access_log_tenant_policy ON body_access_log
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("""
    CREATE POLICY body_access_log_owner_read_policy ON body_access_log
    FOR SELECT
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    for table <-
          ~w(body_snapshots body_snapshot_photos user_health_consents body_settings body_access_log) do
      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end
  end

  # ADR-157's daily sweep releases uploads attached to something that is
  # gone; body photos belong to a snapshot.
  defp dangling_post_media(with_body?) do
    body =
      if with_body?,
        do: """
          WHEN 'body_snapshot' THEN EXISTS (
            SELECT 1 FROM body_snapshots s WHERE s.id = m.attached_id)
        """,
        else: ""

    execute("""
    CREATE OR REPLACE FUNCTION palee_dangling_post_media(cutoff timestamp, max_rows integer)
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
          #{body}
          ELSE true
        END
      ORDER BY m.attached_at
      LIMIT max_rows
    $$
    """)
  end

  # The notification type constraint is rebuilt by several milestones; read
  # its current list instead of restating it, so order never matters.
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
