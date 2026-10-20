defmodule MilosTraining.Repo.Migrations.OpenClubsGroupsAndReports do
  use Ecto.Migration

  # ADR-143 (P2-M4): open clubs, member groups and moderation.
  #
  # - An open club is a club of kind 'open' that staff run for anyone, members
  #   of the gym or not. Its members are explicit rows in
  #   community_club_memberships (status 'pending' while an approval club
  #   hasn't let them in). People read an open club's rows through their own
  #   membership, not through the gym's member list.
  # - A member group is a channel of kind 'member_group' inside the gym club,
  #   proposed by a member when the owner allows it (community_settings).
  #   Its creator is its first admin (community_channel_memberships.role);
  #   a request to join is a membership row with source 'requested'.
  # - community_reports holds what members flagged; staff decide.

  @before_types ~w(
    booking_approved booking_rejected booking_pending booking_timeout workout_note
    workout_changed workout_deleted workout_rejected workout_moved workout_assigned
    workout_assignment_requested review_submitted athlete_message workout_completed
    coaching_message box_message challenge_completed chat_message invoice_issued
    payment_reminder booking_waitlist_promoted package_expiring form_review_submitted
    form_review_completed coaching_reply_overdue nutrition_plan_updated appointment_booked
    appointment_cancelled coach_client_assigned coach_note_viewed inventory_repair_needed
    inventory_stock_low inventory_digest subscription_expiring subscription_grace access_ended
    follow_requested follow_accepted trial_requested trial_booked trial_cancelled
    trial_accepted trial_declined trial_reminder trial_follow_up trial_class_cancelled
  )

  @community_types ~w(
    community_group_proposed community_group_approved community_group_declined
    community_group_join_requested community_group_join_approved community_group_archive_warning
    community_report_created community_club_join_requested community_club_join_approved
  )

  @channel_kinds_before ~w(announcements wod challenges class_slot season custom)
  @channel_kinds @channel_kinds_before ++ ["member_group", "general"]
  @sources_before ~w(opt_in suggested invited auto dismissed)
  @sources @sources_before ++ ["requested"]

  def up do
    # Clubs: what an open club says about itself, who made it.
    alter table(:community_clubs) do
      add :description, :text
      add :cover_media_id, :binary_id
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create constraint(:community_clubs, :community_clubs_description_check,
             check: "description IS NULL OR length(description) <= 1000"
           )

    create index(:community_clubs, [:organization_id, :kind],
             where: "archived_at IS NULL",
             name: :community_clubs_live_kind_index
           )

    # Explicit memberships of open clubs can wait for approval.
    alter table(:community_club_memberships) do
      add :status, :string, null: false, default: "active"
    end

    create constraint(:community_club_memberships, :community_club_memberships_status_check,
             check: "status IN ('active', 'pending')"
           )

    create index(:community_club_memberships, [:user_id, :status])

    # Channels: member groups.
    alter table(:community_channels) do
      add :description, :string
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :join_policy, :string
      add :status, :string, null: false, default: "active"
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :decided_at, :utc_datetime_usec
      add :last_post_at, :utc_datetime_usec
      add :archive_warned_at, :utc_datetime_usec
    end

    replace_check(:community_channels, :community_channels_kind_check, "kind", @channel_kinds)

    # An open club's general channel is built in, named by the app like
    # announcements.
    execute("ALTER TABLE community_channels DROP CONSTRAINT community_channels_name_check")

    create constraint(:community_channels, :community_channels_name_check,
             check:
               "kind IN ('announcements', 'wod', 'challenges', 'general') OR (name IS NOT NULL AND length(btrim(name)) > 0)"
           )

    create constraint(:community_channels, :community_channels_status_check,
             check: "status IN ('pending', 'active', 'declined')"
           )

    create constraint(:community_channels, :community_channels_join_policy_check,
             check:
               "(kind = 'member_group') = (join_policy IS NOT NULL) AND (join_policy IS NULL OR join_policy IN ('open', 'request'))"
           )

    create constraint(:community_channels, :community_channels_description_check,
             check: "description IS NULL OR length(description) <= 200"
           )

    # One live group per name in a club, case-insensitively.
    execute("""
    CREATE UNIQUE INDEX community_channels_group_name_index
    ON community_channels (club_id, lower(name))
    WHERE kind = 'member_group' AND archived_at IS NULL AND status <> 'declined'
    """)

    create index(:community_channels, [:organization_id, :last_post_at],
             where: "kind = 'member_group' AND status = 'active' AND archived_at IS NULL",
             name: :community_channels_quiet_groups_index
           )

    # Channel memberships: group admins and join requests.
    alter table(:community_channel_memberships) do
      add :role, :string, null: false, default: "member"
    end

    create constraint(:community_channel_memberships, :community_channel_memberships_role_check,
             check: "role IN ('member', 'admin')"
           )

    replace_check(
      :community_channel_memberships,
      :community_channel_memberships_source_check,
      "source",
      @sources
    )

    # Comments can be hidden like posts.
    alter table(:community_post_comments) do
      add :hidden_at, :utc_datetime_usec
      add :hidden_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    # The owner's community rules, one row per gym.
    create table(:community_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :member_groups, :string, null: false, default: "approval"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:community_settings, [:organization_id])

    create constraint(:community_settings, :community_settings_member_groups_check,
             check: "member_groups IN ('none', 'approval', 'free')"
           )

    # Reports.
    create table(:community_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :club_id, :binary_id, null: false
      add :channel_id, :binary_id
      add :target_type, :string, null: false
      add :target_id, :binary_id, null: false
      add :target_author_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reporter_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :reason, :string, null: false
      add :note, :string
      add :status, :string, null: false, default: "open"
      add :resolution, :string
      add :resolved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :resolved_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE community_reports
    ADD CONSTRAINT community_reports_club_id_fkey
    FOREIGN KEY (club_id, organization_id)
    REFERENCES community_clubs (id, organization_id) ON DELETE CASCADE
    """)

    create constraint(:community_reports, :community_reports_target_type_check,
             check: "target_type IN ('post', 'comment', 'channel')"
           )

    create constraint(:community_reports, :community_reports_reason_check,
             check: "reason IN ('spam', 'harassment', 'inappropriate', 'other')"
           )

    create constraint(:community_reports, :community_reports_status_check,
             check: "status IN ('open', 'actioned', 'dismissed')"
           )

    create constraint(:community_reports, :community_reports_resolution_check,
             check:
               "(status = 'open') = (resolution IS NULL) AND (resolution IS NULL OR resolution IN ('hidden', 'deleted', 'archived', 'none'))"
           )

    create constraint(:community_reports, :community_reports_note_check,
             check: "note IS NULL OR length(note) <= 500"
           )

    create unique_index(:community_reports, [:target_type, :target_id, :reporter_id])
    create index(:community_reports, [:organization_id, :status, :inserted_at])
    create index(:community_reports, [:target_type, :target_id])

    for table <- ~w(community_settings community_reports), do: secure(table)

    # Open clubs read through the person's own club membership (any gym).
    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_club_ids()
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT m.club_id
      FROM public.community_club_memberships m
      JOIN public.community_clubs c ON c.id = m.club_id
      WHERE m.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
        AND m.status = 'active'
        AND c.kind = 'open'
    $$
    """)

    # Anyone signed in sees a live open club's face (name, description) and
    # its channel list, so they can decide to join.
    execute("""
    CREATE POLICY community_clubs_open_read_policy ON community_clubs
    FOR SELECT
    USING (
      NULLIF(current_setting('app.user_id', true), '') IS NOT NULL
      AND kind = 'open' AND archived_at IS NULL
    )
    """)

    execute("""
    CREATE POLICY community_channels_open_read_policy ON community_channels
    FOR SELECT
    USING (club_id IN (SELECT milos_acting_user_club_ids()))
    """)

    execute("""
    CREATE POLICY community_posts_open_read_policy ON community_posts
    FOR SELECT
    USING (club_id IN (SELECT milos_acting_user_club_ids()))
    """)

    for table <- ~w(community_post_reactions community_post_comments) do
      execute("""
      CREATE POLICY #{table}_open_read_policy ON #{table}
      FOR SELECT
      USING (post_id IN (
        SELECT p.id FROM public.community_posts p
        WHERE p.club_id IN (SELECT milos_acting_user_club_ids())
      ))
      """)
    end

    # A person always sees their own club and channel memberships, at any gym.
    for table <- ~w(community_club_memberships community_channel_memberships) do
      execute("""
      CREATE POLICY #{table}_own_read_policy ON #{table}
      FOR SELECT
      USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      """)
    end

    # A reporter sees their own reports from any session, so what they
    # flagged stays out of their feed (board 7 Q4).
    execute("""
    CREATE POLICY community_reports_own_read_policy ON community_reports
    FOR SELECT
    USING (reporter_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    # How many people an open club has, for anyone deciding to join it.
    execute("""
    CREATE OR REPLACE FUNCTION milos_open_club_member_counts(club_ids uuid[])
    RETURNS TABLE (club_id uuid, member_count bigint)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT m.club_id, count(*)
      FROM public.community_club_memberships m
      JOIN public.community_clubs c ON c.id = m.club_id
      WHERE m.club_id = ANY(club_ids) AND m.status = 'active'
        AND c.kind = 'open' AND c.archived_at IS NULL
      GROUP BY m.club_id
    $$
    """)

    # Fellow members of an open club see each other.
    execute("""
    CREATE POLICY community_club_memberships_open_read_policy ON community_club_memberships
    FOR SELECT
    USING (club_id IN (SELECT milos_acting_user_club_ids()))
    """)

    replace_notification_types(@before_types ++ @community_types)
  end

  def down do
    replace_notification_types(@before_types)

    execute(
      "DROP POLICY IF EXISTS community_club_memberships_open_read_policy ON community_club_memberships"
    )

    for table <- ~w(community_club_memberships community_channel_memberships),
        do: execute("DROP POLICY IF EXISTS #{table}_own_read_policy ON #{table}")

    for table <-
          ~w(community_post_reactions community_post_comments community_posts community_channels community_clubs),
        do: execute("DROP POLICY IF EXISTS #{table}_open_read_policy ON #{table}")

    execute("DROP FUNCTION IF EXISTS milos_open_club_member_counts(uuid[])")
    execute("DROP FUNCTION IF EXISTS milos_acting_user_club_ids()")

    execute("DROP POLICY IF EXISTS community_reports_own_read_policy ON community_reports")
    drop table(:community_reports)
    drop table(:community_settings)

    alter table(:community_post_comments) do
      remove :hidden_at
      remove :hidden_by_id
    end

    replace_check(
      :community_channel_memberships,
      :community_channel_memberships_source_check,
      "source",
      @sources_before
    )

    drop constraint(:community_channel_memberships, :community_channel_memberships_role_check)

    alter table(:community_channel_memberships) do
      remove :role
    end

    execute("DROP INDEX IF EXISTS community_channels_quiet_groups_index")
    execute("DROP INDEX IF EXISTS community_channels_group_name_index")
    drop constraint(:community_channels, :community_channels_description_check)
    drop constraint(:community_channels, :community_channels_join_policy_check)
    drop constraint(:community_channels, :community_channels_status_check)
    execute("DELETE FROM community_channels WHERE kind IN ('member_group', 'general')")
    execute("ALTER TABLE community_channels DROP CONSTRAINT community_channels_name_check")

    create constraint(:community_channels, :community_channels_name_check,
             check:
               "kind IN ('announcements', 'wod', 'challenges') OR (name IS NOT NULL AND length(btrim(name)) > 0)"
           )

    replace_check(
      :community_channels,
      :community_channels_kind_check,
      "kind",
      @channel_kinds_before
    )

    alter table(:community_channels) do
      remove :description
      remove :created_by_id
      remove :join_policy
      remove :status
      remove :decided_by_id
      remove :decided_at
      remove :last_post_at
      remove :archive_warned_at
    end

    drop index(:community_club_memberships, [:user_id, :status])

    drop constraint(:community_club_memberships, :community_club_memberships_status_check)

    alter table(:community_club_memberships) do
      remove :status
    end

    execute("DROP INDEX IF EXISTS community_clubs_live_kind_index")
    drop constraint(:community_clubs, :community_clubs_description_check)

    alter table(:community_clubs) do
      remove :description
      remove :cover_media_id
      remove :created_by_id
    end
  end

  defp replace_check(table, name, column, values) do
    execute("ALTER TABLE #{table} DROP CONSTRAINT IF EXISTS #{name}")

    create constraint(table, name,
             check: "#{column} IN (#{Enum.map_join(values, ", ", &"'#{&1}'")})"
           )
  end

  defp replace_notification_types(types) do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")})"
           )
  end

  defp secure(table) do
    execute("""
    CREATE TRIGGER #{table}_apply_tenant_context
    BEFORE INSERT OR UPDATE ON #{table}
    FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
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
