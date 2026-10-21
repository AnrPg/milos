defmodule MilosTraining.Repo.Migrations.DeviceIntegrations do
  @moduledoc """
  ADR-161 (P2-M13, Garmin; ADR-149): connected health devices.

  - `device_connections`: one row per person and provider (`garmin`, and
    later `apple_health`, `health_connect`). OAuth tokens and the PKCE
    verifier are encrypted at rest by the application (AES-256-GCM); the
    OAuth `state` is stored only as a SHA-256 hash. `sync_prefs` says what is
    brought in (activities, sleep, weight, resting heart rate), `backfill_*`
    tracks the history import chosen at connect (0, 30 or 90 days).
    `consecutive_failures` feeds the health check that marks a connection
    `error` and tells the person once (`error_notified_at`).
  - `device_imports`: every summary a provider sent, deduplicated per person,
    provider, kind and provider id, with a trimmed payload, what it became
    (`target_type`/`target_id`) and how (`imported`, `merged`,
    `needs_confirmation`, `ignored`). The audit trail and the idempotency key
    of the push endpoint.
  - `device_activities`: a workout from the watch. On its own it is a journal
    entry (`state = 'own'`, private, optionally tied to a booked class and its
    gym); merged into a logged workout or an in-app execution it only adds
    the watch's numbers to that entry (`state = 'merged'`); with two possible
    matches it waits for the person (`state = 'pending'`).
  - `daily_stats`: one row per person, day and source with the resting heart
    rate (Πρόοδος).

  All four are the person's own (personal-session RLS, like Σώμα). A coach of
  a gym reads a device activity only while its rung reaches them: its own
  rung for a class-tied activity, the rung of the entry it merged into
  otherwise (`milos_journal_entry_rung`).

  The push endpoint, the OAuth return and the token sweep run without a
  session; narrow SECURITY DEFINER lookups answer ids only. The match lookup
  reads the session person's own workouts and booked classes across gyms.
  """

  use Ecto.Migration

  @providers "('garmin', 'apple_health', 'health_connect')"
  @member_rungs "('private', 'coach_can_view')"
  @notification_types ~w(device_sync_error)

  def up do
    create table(:device_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :provider_user_id, :string
      add :access_token, :binary
      add :refresh_token, :binary
      add :token_expires_at, :utc_datetime_usec
      add :refresh_token_expires_at, :utc_datetime_usec
      add :scopes, {:array, :string}, null: false, default: []

      add :sync_prefs, :map,
        null: false,
        default: %{"activities" => true, "sleep" => true, "weight" => true, "resting_hr" => true}

      add :backfill_days, :integer, null: false, default: 30
      add :backfill_status, :string, null: false, default: "none"
      add :backfill_windows_total, :integer, null: false, default: 0
      add :backfill_windows_done, :integer, null: false, default: 0
      add :oauth_state_hash, :string
      add :pkce_verifier, :binary
      add :oauth_started_at, :utc_datetime_usec
      add :connected_at, :utc_datetime_usec
      add :last_synced_at, :utc_datetime_usec
      add :last_sync_requested_at, :utc_datetime_usec
      add :last_error, :string
      add :consecutive_failures, :integer, null: false, default: 0
      add :error_notified_at, :utc_datetime_usec
      add :imports_seen_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:device_connections, :device_connections_provider_check,
             check: "provider IN #{@providers}"
           )

    create constraint(:device_connections, :device_connections_status_check,
             check: "status IN ('pending', 'active', 'error', 'revoked')"
           )

    create constraint(:device_connections, :device_connections_backfill_check,
             check:
               "backfill_days IN (0, 30, 90) AND " <>
                 "backfill_status IN ('none', 'running', 'done', 'failed') AND " <>
                 "backfill_windows_done BETWEEN 0 AND backfill_windows_total"
           )

    create constraint(:device_connections, :device_connections_prefs_check,
             check: "jsonb_typeof(sync_prefs) = 'object'"
           )

    create unique_index(:device_connections, [:user_id, :provider])

    # A provider account links to one Milos account at a time.
    create unique_index(:device_connections, [:provider, :provider_user_id],
             where: "provider_user_id IS NOT NULL AND status <> 'revoked'",
             name: :device_connections_provider_user_index
           )

    create unique_index(:device_connections, [:oauth_state_hash],
             where: "oauth_state_hash IS NOT NULL"
           )

    create index(:device_connections, [:token_expires_at], where: "status = 'active'")

    create table(:device_activities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all)

      add :provider, :string, null: false
      add :provider_activity_id, :string, null: false
      add :state, :string, null: false, default: "own"
      add :sport, :string, null: false
      add :activity_type, :string
      add :title, :string, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :started_tz, :string, null: false, default: "UTC"
      add :duration_seconds, :integer, null: false
      add :distance_meters, :float
      add :avg_heart_rate, :integer
      add :max_heart_rate, :integer
      add :calories, :integer
      add :class_id, :binary_id
      add :merged_kind, :string
      add :merged_id, :binary_id
      add :candidates, {:array, :map}, null: false, default: []
      add :journal_visibility, :string, null: false, default: "private"

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:device_activities, :device_activities_provider_check,
             check: "provider IN #{@providers}"
           )

    create constraint(:device_activities, :device_activities_state_check,
             check:
               "(state = 'own' AND merged_id IS NULL) OR " <>
                 "(state = 'merged' AND merged_kind IN ('training_log', 'execution') AND merged_id IS NOT NULL) OR " <>
                 "(state = 'pending' AND merged_id IS NULL)"
           )

    create constraint(:device_activities, :device_activities_journal_visibility_check,
             check: "journal_visibility IN #{@member_rungs}"
           )

    create constraint(:device_activities, :device_activities_numbers_check,
             check:
               "duration_seconds >= 0 AND (distance_meters IS NULL OR distance_meters >= 0) AND " <>
                 "(avg_heart_rate IS NULL OR avg_heart_rate BETWEEN 20 AND 260) AND " <>
                 "(max_heart_rate IS NULL OR max_heart_rate BETWEEN 20 AND 260) AND " <>
                 "(calories IS NULL OR calories >= 0)"
           )

    create unique_index(:device_activities, [:user_id, :provider, :provider_activity_id])
    create index(:device_activities, [:user_id, :started_at, :id], where: "state = 'own'")
    create index(:device_activities, [:merged_kind, :merged_id], where: "merged_id IS NOT NULL")
    create index(:device_activities, [:organization_id])

    create table(:device_imports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :connection_id,
          references(:device_connections, type: :binary_id, on_delete: :nilify_all)

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :kind, :string, null: false
      add :provider_id, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :target_type, :string
      add :target_id, :binary_id
      add :status, :string, null: false
      add :reason, :string
      add :received_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:device_imports, :device_imports_provider_check,
             check: "provider IN #{@providers}"
           )

    create constraint(:device_imports, :device_imports_kind_check,
             check: "kind IN ('activity', 'sleep', 'weight', 'daily')"
           )

    create constraint(:device_imports, :device_imports_status_check,
             check: "status IN ('imported', 'merged', 'needs_confirmation', 'ignored')"
           )

    create constraint(:device_imports, :device_imports_target_check,
             check:
               "target_type IS NULL OR target_type IN " <>
                 "('device_activity', 'wellness_entry', 'body_snapshot', 'daily_stat')"
           )

    create unique_index(:device_imports, [:user_id, :provider, :kind, :provider_id])
    create index(:device_imports, [:user_id, :received_at])
    create index(:device_imports, [:connection_id])

    create table(:daily_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :on, :date, null: false
      add :source, :string, null: false
      add :resting_heart_rate, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:daily_stats, :daily_stats_source_check,
             check: "source IN ('manual', 'garmin', 'apple_health', 'health_connect')"
           )

    create constraint(:daily_stats, :daily_stats_resting_check,
             check: "resting_heart_rate IS NULL OR resting_heart_rate BETWEEN 20 AND 200"
           )

    create unique_index(:daily_stats, [:user_id, :on, :source])

    functions()
    policies()
    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    for function <- [
          "milos_device_connection_by_oauth_state(text)",
          "milos_device_connections_for_provider_users(text, text[])",
          "milos_device_connections_due_refresh(timestamp, integer)",
          "milos_device_match_candidates(timestamp, timestamp)"
        ] do
      execute("DROP FUNCTION IF EXISTS #{function}")
    end

    drop table(:daily_stats)
    drop table(:device_imports)
    drop table(:device_activities)
    drop table(:device_connections)
  end

  defp functions do
    # The OAuth return: which pending connection started this sign-in.
    execute("""
    CREATE FUNCTION milos_device_connection_by_oauth_state(p_state_hash text)
    RETURNS TABLE (id uuid, user_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT c.id, c.user_id FROM public.device_connections c
      WHERE c.oauth_state_hash = p_state_hash AND c.oauth_state_hash IS NOT NULL
    $$
    """)

    # The push endpoint: which connections the provider's user ids belong to.
    execute("""
    CREATE FUNCTION milos_device_connections_for_provider_users(p_provider text, p_user_ids text[])
    RETURNS TABLE (id uuid, user_id uuid, provider_user_id text, status text)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT c.id, c.user_id, c.provider_user_id, c.status FROM public.device_connections c
      WHERE c.provider = p_provider
        AND c.provider_user_id = ANY (p_user_ids)
        AND c.status <> 'revoked'
    $$
    """)

    # The token sweep: active or failing connections whose access token ends soon.
    execute("""
    CREATE FUNCTION milos_device_connections_due_refresh(p_before timestamp, p_lim integer)
    RETURNS TABLE (id uuid, user_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT c.id, c.user_id FROM public.device_connections c
      WHERE c.status IN ('active', 'error')
        AND c.refresh_token IS NOT NULL
        AND c.token_expires_at IS NOT NULL
        AND c.token_expires_at < p_before
      ORDER BY c.token_expires_at
      LIMIT p_lim
    $$
    """)

    # What a watch activity could belong to, for the session's person only:
    # logged workouts, finished in-app executions and approved or attended
    # classes not logged yet, in every gym, between two instants.
    execute("""
    CREATE FUNCTION milos_device_match_candidates(p_from timestamp, p_to timestamp)
    RETURNS TABLE (
      kind text, id uuid, organization_id uuid, title text,
      starts_at timestamp, ends_at timestamp
    )
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      WITH me AS (
        SELECT NULLIF(current_setting('app.user_id', true), '')::uuid AS id
      )
      SELECT 'training_log', l.id, l.organization_id, l.title,
             l.performed_at_utc::timestamp,
             (l.performed_at_utc + make_interval(secs => COALESCE(l.duration_seconds, 3600)))::timestamp
      FROM public.training_log_entries l, me
      WHERE l.user_id = me.id AND l.status = 'logged'
        AND l.performed_at_utc < p_to
        AND l.performed_at_utc + make_interval(secs => COALESCE(l.duration_seconds, 3600)) > p_from
      UNION ALL
      SELECT 'execution', e.id, e.organization_id, COALESCE(w.title, 'Workout'),
             e.started_at_utc::timestamp, e.completed_at_utc::timestamp
      FROM public.workout_executions e
      LEFT JOIN public.master_workouts w ON w.id = e.master_workout_id, me
      WHERE e.user_id = me.id AND e.status = 'completed'
        AND e.completed_at_utc IS NOT NULL
        AND e.started_at_utc < p_to AND e.completed_at_utc > p_from
      UNION ALL
      SELECT 'class', s.id, s.organization_id, s.name,
             s.scheduled_at::timestamp,
             (s.scheduled_at + make_interval(mins => COALESCE(s.duration_minutes, 60)))::timestamp
      FROM public.scheduled_classes s, me
      WHERE s.scheduled_at < p_to
        AND s.scheduled_at + make_interval(mins => COALESCE(s.duration_minutes, 60)) > p_from
        AND (
          EXISTS (
            SELECT 1 FROM public.bookings b
            WHERE b.scheduled_class_id = s.id AND b.user_id = me.id AND b.status = 'approved'
          )
          OR EXISTS (
            SELECT 1 FROM public.class_attendance_records a
            WHERE a.scheduled_class_id = s.id AND a.user_id = me.id AND a.status = 'attended'
          )
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.training_log_entries l
          WHERE l.user_id = me.id AND l.status = 'logged'
            AND l.source_type = 'class' AND l.source_reference_id = s.id
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.workout_executions e
          LEFT JOIN public.bookings b ON b.id = e.source_reference_id
          WHERE e.user_id = me.id AND e.source = 'class_booking'
            AND (e.source_reference_id = s.id OR b.scheduled_class_id = s.id)
        )
    $$
    """)
  end

  defp policies do
    for table <- ~w(device_connections device_activities device_imports daily_stats) do
      execute("""
      CREATE POLICY #{table}_owner_policy ON #{table}
      USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      """)
    end

    # The watch's numbers follow the entry they belong to.
    execute("""
    CREATE POLICY device_activities_coach_read_policy ON device_activities
    FOR SELECT
    USING (
      state <> 'pending'
      AND milos_entry_visible_to_acting_coach(
        user_id,
        organization_id,
        CASE WHEN merged_id IS NULL THEN journal_visibility
             ELSE milos_journal_entry_rung(merged_kind, merged_id) END
      )
    )
    """)

    for table <- ~w(device_connections device_activities device_imports daily_stats) do
      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end
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
