defmodule Palee.Repo.Migrations.AddJournalVisibilityLadder do
  @moduledoc """
  ADR-139: one visibility ladder on every journal entry type.

  * `palee_journal_visibility_reaches_coach/1` is the single SQL definition of
    "this rung lets the member's coach read the entry".
  * `journal_visibility` on executions, training-log entries, PRs and injuries,
    backfilled from what coaches could already see: executions and log entries
    done in a gym and every injury -> `coach_can_view`; personal executions ->
    `private`; PRs from their owner's ADR-129 `coach_visibility` switch.
  * `journal_visibility_defaults` holds a member's default rung per kind. The
    PR switch becomes the `pr` default and `user_pr_sharing_preferences` is
    dropped; `down` rebuilds it from the defaults.
  * The ADR-129 coach read policy on PRs asks the record's own rung instead of
    the owner's switch, through `palee_entry_visible_to_acting_coach/3`, which
    the new entry tables reuse.

  Runs as the migration role, which is not subject to the owner-only RLS
  policies on these personal tables.
  """

  use Ecto.Migration

  # `rated` belongs to reviews alone, which store no ladder column (ADR-139).
  @chosen_by_member ~w(private coach_can_view coach_reply_requested posted)

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION palee_journal_visibility_reaches_coach(visibility text)
    RETURNS boolean
    LANGUAGE sql
    IMMUTABLE
    AS $$
      SELECT visibility IN ('coach_can_view', 'coach_reply_requested', 'rated', 'posted')
    $$
    """)

    add_ladder(:workout_executions, "coach_can_view", @chosen_by_member)
    add_ladder(:training_log_entries, "coach_can_view", @chosen_by_member)
    add_ladder(:user_pr_records, "coach_can_view", @chosen_by_member)
    # Coaches always see injuries (vision §4.5): no private rung.
    add_ladder(:injury_reports, "coach_can_view", ~w(coach_can_view coach_reply_requested posted))

    execute(
      "UPDATE workout_executions SET journal_visibility = 'private' WHERE organization_id IS NULL"
    )

    execute("""
    UPDATE user_pr_records records
    SET journal_visibility = 'private'
    FROM user_pr_sharing_preferences pref
    WHERE pref.user_id = records.user_id AND pref.coach_visibility = false
    """)

    create table(:journal_visibility_defaults, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :kind, :string, primary_key: true
      add :visibility, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:journal_visibility_defaults, :journal_visibility_defaults_kind_check,
             check: "kind IN ('workout', 'pr', 'note', 'check_in')"
           )

    create constraint(:journal_visibility_defaults, :journal_visibility_defaults_rung_check,
             check: "visibility IN ('private', 'coach_can_view')"
           )

    execute("""
    INSERT INTO journal_visibility_defaults (user_id, kind, visibility, inserted_at, updated_at)
    SELECT user_id, 'pr', 'private', inserted_at, updated_at
    FROM user_pr_sharing_preferences
    WHERE coach_visibility = false
    """)

    execute("""
    CREATE POLICY journal_visibility_defaults_owner_policy ON journal_visibility_defaults
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("ALTER TABLE journal_visibility_defaults ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE journal_visibility_defaults FORCE ROW LEVEL SECURITY")

    # The owner's membership is invisible to the coach's session, hence
    # SECURITY DEFINER. It answers one boolean about one entry, only for the
    # gym the session is scoped to (same shape as ADR-129's PR check).
    execute("""
    CREATE OR REPLACE FUNCTION palee_entry_visible_to_acting_coach(
      entry_user_id uuid, entry_org_id uuid, visibility text
    )
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT entry_org_id IS NOT NULL
        AND public.palee_journal_visibility_reaches_coach(visibility)
        AND entry_org_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
        AND public.palee_acting_user_coaches(entry_org_id)
        AND EXISTS (
          SELECT 1
          FROM public.organization_memberships target
          WHERE target.organization_id = entry_org_id
            AND target.user_id = entry_user_id
            AND target.status = 'active'
        )
    $$
    """)

    execute("DROP POLICY IF EXISTS user_pr_records_coach_read_policy ON user_pr_records")

    execute("""
    CREATE POLICY user_pr_records_coach_read_policy ON user_pr_records
    FOR SELECT
    USING (palee_entry_visible_to_acting_coach(user_id, organization_id, journal_visibility))
    """)

    execute("DROP FUNCTION IF EXISTS palee_pr_visible_to_acting_coach(uuid, uuid)")
    drop table(:user_pr_sharing_preferences)
  end

  def down do
    create table(:user_pr_sharing_preferences, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :coach_visibility, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    INSERT INTO user_pr_sharing_preferences (user_id, coach_visibility, inserted_at, updated_at)
    SELECT user_id, false, inserted_at, updated_at
    FROM journal_visibility_defaults
    WHERE kind = 'pr' AND visibility = 'private'
    """)

    execute("""
    CREATE POLICY user_pr_sharing_preferences_owner_policy ON user_pr_sharing_preferences
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("ALTER TABLE user_pr_sharing_preferences ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE user_pr_sharing_preferences FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE OR REPLACE FUNCTION palee_pr_visible_to_acting_coach(pr_user_id uuid, pr_org_id uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT pr_org_id IS NOT NULL
        AND pr_org_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
        AND public.palee_acting_user_coaches(pr_org_id)
        AND EXISTS (
          SELECT 1
          FROM public.organization_memberships target
          WHERE target.organization_id = pr_org_id
            AND target.user_id = pr_user_id
            AND target.status = 'active'
        )
        AND NOT EXISTS (
          SELECT 1
          FROM public.user_pr_sharing_preferences pref
          WHERE pref.user_id = pr_user_id
            AND pref.coach_visibility = false
        )
    $$
    """)

    execute("DROP POLICY IF EXISTS user_pr_records_coach_read_policy ON user_pr_records")

    execute("""
    CREATE POLICY user_pr_records_coach_read_policy ON user_pr_records
    FOR SELECT
    USING (palee_pr_visible_to_acting_coach(user_id, organization_id))
    """)

    execute("DROP FUNCTION IF EXISTS palee_entry_visible_to_acting_coach(uuid, uuid, text)")

    drop table(:journal_visibility_defaults)

    for table <- ~w(injury_reports user_pr_records training_log_entries workout_executions)a do
      alter table(table) do
        remove :journal_visibility
      end
    end

    execute("DROP FUNCTION IF EXISTS palee_journal_visibility_reaches_coach(text)")
  end

  defp add_ladder(table, default, allowed) do
    alter table(table) do
      add :journal_visibility, :string, null: false, default: default
    end

    values = Enum.map_join(allowed, ", ", &"'#{&1}'")

    create constraint(table, :"#{table}_journal_visibility_check",
             check: "journal_visibility IN (#{values})"
           )
  end
end
