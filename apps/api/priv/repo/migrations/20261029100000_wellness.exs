defmodule MilosTraining.Repo.Migrations.Wellness do
  @moduledoc """
  ADR-159: Ημερολόγιο › Ευεξία (vision §7.7, mockups 21–22).

  - `wellness_entries`: one row per logged fact of a kind (`water`, `sleep`,
    `meal`), with a kind-specific `value` the domain validates, the instant
    it happened, the member's zone then and the local day it counts for. A
    glass of water is an entry, so undo is a delete and the day total is a
    sum. Devices (Garmin, M13) write the same rows with their own `source`
    and `external_id`, deduplicated per source; a member's correction of a
    device row sets `corrected_at` and later syncs leave it alone.
  - `craving_entries`: Λιγούρα, with intensity, causes, an outcome that may
    come later, a support request and an optional follow-up time.
  - `wellness_preferences`: the member's own water goal, glass size and sleep
    goal, and the items they turned off.

  Like Πώς νιώθω (ADR-139/140), entries are personal data with optional gym
  provenance: the owner reads and writes them in any session; a coach of the
  provenance gym reads them only while their rung reaches the coach.
  Preferences are the owner's alone.
  """

  use Ecto.Migration

  @member_rungs "('private', 'coach_can_view', 'coach_reply_requested', 'posted')"

  def change do
    create table(:wellness_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all)

      add :kind, :string, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :occurred_tz, :string, null: false, default: "UTC"
      add :occurred_on, :date, null: false
      add :value, :map, null: false, default: %{}
      add :source, :string, null: false, default: "manual"
      add :external_id, :string
      add :corrected_at, :utc_datetime_usec
      add :journal_visibility, :string, null: false, default: "private"
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:wellness_entries, :wellness_entries_kind_check,
             check: "kind IN ('water', 'sleep', 'meal')"
           )

    create constraint(:wellness_entries, :wellness_entries_source_check,
             check: "source IN ('manual', 'garmin', 'apple_health', 'health_connect')"
           )

    create constraint(:wellness_entries, :wellness_entries_external_check,
             check: "(source = 'manual') = (external_id IS NULL)"
           )

    create constraint(:wellness_entries, :wellness_entries_value_check,
             check: "jsonb_typeof(value) = 'object'"
           )

    create constraint(:wellness_entries, :wellness_entries_journal_visibility_check,
             check: "journal_visibility IN #{@member_rungs}"
           )

    create index(:wellness_entries, [:user_id, :occurred_on, :kind], where: "deleted_at IS NULL")

    create index(:wellness_entries, [:user_id, :occurred_at], where: "deleted_at IS NULL")
    create index(:wellness_entries, [:organization_id])

    create unique_index(:wellness_entries, [:user_id, :source, :external_id],
             where: "external_id IS NOT NULL",
             name: :wellness_entries_device_unique
           )

    create table(:craving_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all)

      add :occurred_at, :utc_datetime_usec, null: false
      add :occurred_tz, :string, null: false, default: "UTC"
      add :occurred_on, :date, null: false
      add :intensity, :smallint, null: false
      add :triggers, {:array, :string}, null: false, default: []
      add :outcome, :string
      add :outcome_at, :utc_datetime_usec
      add :note, :text
      add :support_requested_at, :utc_datetime_usec
      add :follow_up_at, :utc_datetime_usec
      add :followed_up_at, :utc_datetime_usec
      add :journal_visibility, :string, null: false, default: "private"
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:craving_entries, :craving_entries_intensity_check,
             check: "intensity BETWEEN 1 AND 10"
           )

    create constraint(:craving_entries, :craving_entries_triggers_check,
             check:
               "triggers <@ ARRAY['stress', 'fatigue', 'boredom', 'social', 'hunger', 'other']::varchar[]"
           )

    create constraint(:craving_entries, :craving_entries_outcome_check,
             check:
               "(outcome IS NULL AND outcome_at IS NULL) OR " <>
                 "(outcome IN ('ongoing', 'resisted', 'ate_off_plan') AND outcome_at IS NOT NULL)"
           )

    create constraint(:craving_entries, :craving_entries_note_check,
             check: "note IS NULL OR char_length(note) BETWEEN 1 AND 500"
           )

    create constraint(:craving_entries, :craving_entries_journal_visibility_check,
             check: "journal_visibility IN #{@member_rungs}"
           )

    create index(:craving_entries, [:user_id, :occurred_on], where: "deleted_at IS NULL")
    create index(:craving_entries, [:user_id, :occurred_at], where: "deleted_at IS NULL")
    create index(:craving_entries, [:organization_id])

    # The follow-up sweep: cravings still on «Ακόμα την έχω» whose ask is due.
    create index(:craving_entries, [:follow_up_at],
             where: "follow_up_at IS NOT NULL AND followed_up_at IS NULL AND deleted_at IS NULL"
           )

    create table(:wellness_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :water_goal_ml, :integer, null: false, default: 2000
      add :glass_ml, :integer, null: false, default: 250
      add :sleep_goal_minutes, :integer, null: false, default: 420
      add :hidden_items, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:wellness_preferences, [:user_id])

    create constraint(:wellness_preferences, :wellness_preferences_water_check,
             check:
               "water_goal_ml BETWEEN 250 AND 8000 AND glass_ml BETWEEN 50 AND 2000 " <>
                 "AND sleep_goal_minutes BETWEEN 240 AND 720"
           )

    create constraint(:wellness_preferences, :wellness_preferences_hidden_items_check,
             check: "hidden_items <@ ARRAY['water', 'sleep', 'meals', 'plan', 'mood']::varchar[]"
           )

    for table <- ~w(wellness_entries craving_entries) do
      execute(
        """
        CREATE POLICY #{table}_owner_policy ON #{table}
        USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
        WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
        """,
        "DROP POLICY IF EXISTS #{table}_owner_policy ON #{table}"
      )

      execute(
        """
        CREATE POLICY #{table}_coach_read_policy ON #{table}
        FOR SELECT
        USING (
          deleted_at IS NULL
          AND milos_entry_visible_to_acting_coach(user_id, organization_id, journal_visibility)
        )
        """,
        "DROP POLICY IF EXISTS #{table}_coach_read_policy ON #{table}"
      )
    end

    execute(
      """
      CREATE POLICY wellness_preferences_owner_policy ON wellness_preferences
      USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS wellness_preferences_owner_policy ON wellness_preferences"
    )

    for table <- ~w(wellness_entries craving_entries wellness_preferences) do
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
end
