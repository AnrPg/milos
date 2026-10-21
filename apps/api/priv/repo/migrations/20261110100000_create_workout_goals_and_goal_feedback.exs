defmodule MilosTraining.Repo.Migrations.CreateWorkoutGoalsAndGoalFeedback do
  @moduledoc """
  ADR-163: WOD goals.

  `workout_goals` holds the coach's goals for one master workout (muscles
  with roles, fitness qualities, a stimulus line) and whether members see
  them. It is tenant content: the bare tenant policy, the same protection as
  `master_workouts`; which members see a row (`visible_to_members`) is
  decided by the use case, as with the workout itself. Deleting the workout
  deletes its goals.

  `goal_feedback` is what an athlete says they felt after one of their own
  journal entries (an execution or a training-log entry). It is the
  member's own data, like a journal comment: owner-only writes (the entry
  must be theirs), and a coach reads it only while the entry's rung reaches
  them, exactly as `journal_comments`.
  """

  use Ecto.Migration

  def up do
    create table(:workout_goals, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :master_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :muscles, :jsonb, null: false, default: fragment("'[]'::jsonb")
      add :qualities, {:array, :text}, null: false, default: []
      add :stimulus, :text
      add :visible_to_members, :boolean, null: false, default: false
      add :source, :text, null: false, default: "suggested"
      add :taxonomy_version, :integer, null: false
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workout_goals, [:master_workout_id])
    create index(:workout_goals, [:organization_id])

    create constraint(:workout_goals, :workout_goals_source_check,
             check: "source IN ('suggested', 'edited')"
           )

    create constraint(:workout_goals, :workout_goals_muscles_check,
             check: "jsonb_typeof(muscles) = 'array'"
           )

    create constraint(:workout_goals, :workout_goals_stimulus_check,
             check: "stimulus IS NULL OR char_length(stimulus) BETWEEN 1 AND 280"
           )

    execute("""
    CREATE TRIGGER workout_goals_apply_tenant_context
    BEFORE INSERT OR UPDATE ON workout_goals
    FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY workout_goals_tenant_policy ON workout_goals
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE workout_goals ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE workout_goals FORCE ROW LEVEL SECURITY")

    create table(:goal_feedback, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all)

      add :entry_kind, :text, null: false
      add :entry_id, :binary_id, null: false
      add :felt_muscles, {:array, :text}, null: false, default: []
      add :felt_qualities, {:array, :text}, null: false, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:goal_feedback, [:entry_kind, :entry_id, :user_id])
    create index(:goal_feedback, [:user_id, :inserted_at])
    create index(:goal_feedback, [:organization_id])

    create constraint(:goal_feedback, :goal_feedback_entry_kind_check,
             check: "entry_kind IN ('execution', 'training_log')"
           )

    # The entry a feedback row is about: its owner, gym, workout and whether
    # it was voided. SECURITY DEFINER for the same reason as
    # milos_journal_entry_owner: executions and logs sit under other scopes
    # than the member's feedback routes. It answers about one entry.
    execute("""
    CREATE OR REPLACE FUNCTION milos_goal_feedback_entry(kind text, entry uuid)
    RETURNS TABLE (user_id uuid, organization_id uuid, master_workout_id uuid, voided boolean)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT e.user_id, e.organization_id, e.master_workout_id, false
      FROM workout_executions e
      WHERE kind = 'execution' AND e.id = entry
      UNION ALL
      SELECT l.user_id, l.organization_id, l.master_workout_id, l.voided_at IS NOT NULL
      FROM training_log_entries l
      WHERE kind = 'training_log' AND l.id = entry
    $$
    """)

    execute("""
    CREATE POLICY goal_feedback_owner_policy ON goal_feedback
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      AND user_id = (SELECT owner.user_id FROM milos_journal_entry_owner(entry_kind, entry_id) owner)
    )
    """)

    execute("""
    CREATE POLICY goal_feedback_coach_read_policy ON goal_feedback
    FOR SELECT
    USING (
      milos_entry_visible_to_acting_coach(
        user_id, organization_id, milos_journal_entry_rung(entry_kind, entry_id)
      )
    )
    """)

    execute("""
    CREATE POLICY goal_feedback_coach_shared_read_policy ON goal_feedback
    FOR SELECT
    USING (
      milos_entry_shared_with_acting_coach(
        entry_kind, entry_id, user_id, organization_id,
        milos_journal_entry_rung(entry_kind, entry_id)
      )
    )
    """)

    execute("ALTER TABLE goal_feedback ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE goal_feedback FORCE ROW LEVEL SECURITY")
  end

  def down do
    drop table(:goal_feedback)
    execute("DROP FUNCTION IF EXISTS milos_goal_feedback_entry(text, uuid)")
    drop table(:workout_goals)
  end
end
