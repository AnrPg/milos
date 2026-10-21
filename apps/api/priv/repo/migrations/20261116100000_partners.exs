defmodule Palee.Repo.Migrations.Partners do
  @moduledoc """
  ADR-169 (P3-M7, Partners): training partners inside a club.

  Tenant data of the club's gym (`organization_id` is the club's gym; the
  gym's tenant policy; purged with the gym):

  - `partner_profiles`: one per club and person; `active` (the member's
    opt-in), level, times, goals, an optional `about`, an optional `gender`
    used only to honour preferences, `gender_preference`, and
    `suspended_at` when staff hid it after a report.
  - `partner_swipes`: one per club and pair, `like` or `pass`
    (`updated_at` is when it was last made; a pass expires after 30 days).
  - `partner_matches`: the pair ordered `user_a_id < user_b_id`, at most
    one active per gym and pair; how it ended; each side's read mark.
  - `partner_messages`: the pair's conversation; a `plan` message carries a
    class and a snapshot of it («Κλείστε μαζί»).

  Personal (owner-only):

  - `community_user_blocks`: whom a person blocked. `palee_blocked_user_ids`
    (SECURITY DEFINER) answers, for the session user only, whom they
    blocked or were blocked by.

  Also: `community_reports.target_type` gains `partner`,
  `community_settings.partners_enabled` (on by default), and the
  notification types `partner_match`, `partner_message`.
  """

  use Ecto.Migration

  @notification_types ~w(partner_match partner_message)
  @tenant_tables ~w(partner_profiles partner_swipes partner_matches partner_messages)

  def up do
    create table(:partner_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :club_id, references(:community_clubs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :active, :boolean, null: false, default: true
      add :level, :text, null: false
      add :times, {:array, :text}, null: false, default: []
      add :goals, {:array, :text}, null: false, default: []
      add :about, :text
      add :gender, :text
      add :gender_preference, :text, null: false, default: "any"
      add :suspended_at, :utc_datetime_usec
      add :suspended_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:partner_profiles, [:club_id, :user_id])
    create index(:partner_profiles, [:organization_id])
    create index(:partner_profiles, [:user_id])

    create constraint(:partner_profiles, :partner_profiles_level_check,
             check: "level IN ('beginner', 'intermediate', 'advanced')"
           )

    create constraint(:partner_profiles, :partner_profiles_times_check,
             check:
               "times <@ ARRAY['early', 'midday', 'afternoon', 'evening', 'weekend']::text[] " <>
                 "AND cardinality(times) BETWEEN 1 AND 5"
           )

    create constraint(:partner_profiles, :partner_profiles_goals_check,
             check:
               "goals <@ ARRAY['strength', 'conditioning', 'weight_loss', 'skills', " <>
                 "'competition', 'consistency']::text[] AND cardinality(goals) BETWEEN 1 AND 3"
           )

    create constraint(:partner_profiles, :partner_profiles_about_check,
             check: "about IS NULL OR char_length(about) BETWEEN 1 AND 140"
           )

    create constraint(:partner_profiles, :partner_profiles_gender_check,
             check: "gender IS NULL OR gender IN ('woman', 'man', 'other')"
           )

    create constraint(:partner_profiles, :partner_profiles_gender_preference_check,
             check: "gender_preference IN ('any', 'women', 'men')"
           )

    create table(:partner_swipes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :club_id, references(:community_clubs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :swiper_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :target_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :direction, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:partner_swipes, [:club_id, :swiper_id, :target_id])
    create index(:partner_swipes, [:club_id, :target_id, :direction])
    create index(:partner_swipes, [:swiper_id, :updated_at])
    create index(:partner_swipes, [:organization_id])

    create constraint(:partner_swipes, :partner_swipes_direction_check,
             check: "direction IN ('like', 'pass')"
           )

    create constraint(:partner_swipes, :partner_swipes_pair_check,
             check: "swiper_id <> target_id"
           )

    create table(:partner_matches, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :club_id, references(:community_clubs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_a_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :user_b_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :text, null: false, default: "active"
      add :matched_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec
      add :ended_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :end_reason, :text
      add :a_read_at, :utc_datetime_usec
      add :b_read_at, :utc_datetime_usec
      add :last_message_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:partner_matches, [:organization_id, :user_a_id, :user_b_id],
             where: "status = 'active'",
             name: :partner_matches_active_pair_index
           )

    create index(:partner_matches, [:user_a_id, :status])
    create index(:partner_matches, [:user_b_id, :status])
    create index(:partner_matches, [:club_id])

    create constraint(:partner_matches, :partner_matches_pair_check,
             check: "user_a_id < user_b_id"
           )

    create constraint(:partner_matches, :partner_matches_status_check,
             check: "status IN ('active', 'ended')"
           )

    create constraint(:partner_matches, :partner_matches_end_check,
             check:
               "(status = 'active' AND ended_at IS NULL AND end_reason IS NULL) OR " <>
                 "(status = 'ended' AND ended_at IS NOT NULL AND end_reason IN " <>
                 "('unmatched', 'blocked', 'reported', 'left', 'hidden'))"
           )

    create table(:partner_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :match_id, references(:partner_matches, type: :binary_id, on_delete: :delete_all),
        null: false

      add :author_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :text, null: false, default: "text"
      add :body, :text

      add :scheduled_class_id,
          references(:scheduled_classes, type: :binary_id, on_delete: :nilify_all)

      add :plan, :jsonb

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:partner_messages, [:match_id, :inserted_at, :id])
    create index(:partner_messages, [:organization_id])

    create constraint(:partner_messages, :partner_messages_kind_check,
             check:
               "(kind = 'text' AND body IS NOT NULL AND plan IS NULL) OR " <>
                 "(kind = 'plan' AND plan IS NOT NULL AND jsonb_typeof(plan) = 'object')"
           )

    create constraint(:partner_messages, :partner_messages_body_check,
             check: "body IS NULL OR char_length(body) BETWEEN 1 AND 2000"
           )

    # A row's gym is its club's gym (and a message's, its match's): the
    # tenant trigger stamps the session's gym, these keys refuse any other.
    execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS community_clubs_id_organization_id_index " <>
        "ON community_clubs (id, organization_id)"
    )

    create unique_index(:partner_matches, [:id, :organization_id])

    for table <- ~w(partner_profiles partner_swipes partner_matches) do
      execute("""
      ALTER TABLE #{table} ADD CONSTRAINT #{table}_club_gym_fkey
      FOREIGN KEY (club_id, organization_id)
      REFERENCES community_clubs (id, organization_id) ON DELETE CASCADE
      """)
    end

    execute("""
    ALTER TABLE partner_messages ADD CONSTRAINT partner_messages_match_gym_fkey
    FOREIGN KEY (match_id, organization_id)
    REFERENCES partner_matches (id, organization_id) ON DELETE CASCADE
    """)

    for table <- @tenant_tables do
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

    create table(:community_user_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :blocked_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:community_user_blocks, [:user_id, :blocked_user_id])
    create index(:community_user_blocks, [:blocked_user_id])

    create constraint(:community_user_blocks, :community_user_blocks_pair_check,
             check: "user_id <> blocked_user_id"
           )

    execute("""
    CREATE POLICY community_user_blocks_owner_policy ON community_user_blocks
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("ALTER TABLE community_user_blocks ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE community_user_blocks FORCE ROW LEVEL SECURITY")

    # Whom the session user blocked or was blocked by: ids only, and only for
    # the session user, so nobody can ask about anyone else's blocks.
    execute("""
    CREATE OR REPLACE FUNCTION palee_blocked_user_ids()
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT b.blocked_user_id FROM community_user_blocks b
      WHERE b.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      UNION
      SELECT b.user_id FROM community_user_blocks b
      WHERE b.blocked_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
    $$
    """)

    alter table(:community_settings) do
      add :partners_enabled, :boolean, null: false, default: true
    end

    execute("ALTER TABLE community_reports DROP CONSTRAINT community_reports_target_type_check")

    create constraint(:community_reports, :community_reports_target_type_check,
             check: "target_type IN ('post', 'comment', 'channel', 'partner')"
           )

    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    execute("DELETE FROM community_reports WHERE target_type = 'partner'")
    execute("ALTER TABLE community_reports DROP CONSTRAINT community_reports_target_type_check")

    create constraint(:community_reports, :community_reports_target_type_check,
             check: "target_type IN ('post', 'comment', 'channel')"
           )

    alter table(:community_settings) do
      remove :partners_enabled
    end

    execute("DROP FUNCTION IF EXISTS palee_blocked_user_ids()")
    drop table(:community_user_blocks)
    drop table(:partner_messages)
    drop table(:partner_matches)
    drop table(:partner_swipes)
    drop table(:partner_profiles)
    execute("DROP INDEX IF EXISTS community_clubs_id_organization_id_index")
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
