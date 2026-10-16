defmodule MilosTraining.Repo.Migrations.CreateJournalComments do
  @moduledoc """
  ADR-140 §1: one Σχόλιο store for text a member writes on their own entry,
  wherever it is written (execution NoteModal, FinishWizard, Καταγραφή, PR,
  later from the card). A comment has an anchor (the whole entry, a section,
  an exercise or a text selection), optional text and tags, and optionally a
  structured change in the old modification-patch shape. It has no rung of
  its own: a coach reads it only while the entry's rung reaches them.

  Moves `workout_executions.exercise_notes` / `exercise_modifications`,
  `training_log_entries.notes` / `exercise_modifications` /
  `performed_exercises[].note` and PR notes (current and history) into
  comments, then drops those columns. `coaching_aggregates` counts recent
  executions with comments instead of the old notes array.
  """

  use Ecto.Migration

  def up do
    create table(:journal_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all)

      add :entry_kind, :string, null: false
      add :entry_id, :binary_id, null: false
      add :section_id, :string
      add :exercise_id, :string
      add :selected_text, :text
      add :selection_start, :integer
      add :selection_end, :integer
      add :tags, {:array, :string}, null: false, default: []
      add :body, :text
      add :change, :map
      add :change_key, :string
      add :written_at, :utc_datetime_usec, null: false
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:journal_comments, :journal_comments_entry_kind_check,
             check: "entry_kind IN ('execution', 'training_log', 'pr')"
           )

    create constraint(:journal_comments, :journal_comments_content_check,
             check: "body IS NOT NULL OR change IS NOT NULL OR cardinality(tags) > 0"
           )

    create constraint(:journal_comments, :journal_comments_body_check,
             check: "body IS NULL OR char_length(body) BETWEEN 1 AND 4000"
           )

    create constraint(:journal_comments, :journal_comments_selection_check,
             check:
               "(selection_start IS NULL AND selection_end IS NULL) OR " <>
                 "(selection_start >= 0 AND selection_end > selection_start)"
           )

    create index(:journal_comments, [:entry_kind, :entry_id], where: "deleted_at IS NULL")
    create index(:journal_comments, [:user_id, :written_at], where: "deleted_at IS NULL")
    create index(:journal_comments, [:organization_id])

    # A structured change is upserted by its stable key (one per row and field).
    create unique_index(:journal_comments, [:entry_kind, :entry_id, :change_key],
             where: "change_key IS NOT NULL AND deleted_at IS NULL",
             name: :journal_comments_change_key_index
           )

    # The rung of the commented entry, for the coach read policy. SECURITY
    # DEFINER so the policy can ask about an entry the session may not read
    # directly; it answers one text about one entry.
    execute("""
    CREATE OR REPLACE FUNCTION milos_journal_entry_rung(kind text, entry uuid)
    RETURNS text
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT CASE kind
        WHEN 'execution' THEN (SELECT journal_visibility FROM workout_executions WHERE id = entry)
        WHEN 'training_log' THEN (SELECT journal_visibility FROM training_log_entries WHERE id = entry)
        WHEN 'pr' THEN (SELECT journal_visibility FROM user_pr_records WHERE id = entry)
      END
    $$
    """)

    # Who owns an entry and in which gym it was done: a comment is written
    # only by the entry's owner and carries the entry's gym. SECURITY DEFINER
    # because executions, logs and PRs sit under different tenant scopes than
    # the user-scoped comment routes.
    execute("""
    CREATE OR REPLACE FUNCTION milos_journal_entry_owner(kind text, entry uuid)
    RETURNS TABLE (user_id uuid, organization_id uuid)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT e.user_id, e.organization_id FROM workout_executions e
      WHERE kind = 'execution' AND e.id = entry
      UNION ALL
      SELECT l.user_id, l.organization_id FROM training_log_entries l
      WHERE kind = 'training_log' AND l.id = entry
      UNION ALL
      SELECT p.user_id, p.organization_id FROM user_pr_records p
      WHERE kind = 'pr' AND p.id = entry
    $$
    """)

    execute("""
    CREATE POLICY journal_comments_owner_policy ON journal_comments
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      AND user_id = (SELECT owner.user_id FROM milos_journal_entry_owner(entry_kind, entry_id) owner)
    )
    """)

    execute("""
    CREATE POLICY journal_comments_coach_read_policy ON journal_comments
    FOR SELECT
    USING (
      deleted_at IS NULL
      AND milos_entry_visible_to_acting_coach(
        user_id, organization_id, milos_journal_entry_rung(entry_kind, entry_id)
      )
    )
    """)

    execute("ALTER TABLE journal_comments ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE journal_comments FORCE ROW LEVEL SECURITY")

    migrate_execution_notes()
    migrate_modifications("execution", "workout_executions", "inserted_at")
    migrate_modifications("training_log", "training_log_entries", "performed_at_utc")
    migrate_training_log_text()
    migrate_pr_notes()

    recreate_coaching_aggregates("""
    EXISTS (
      SELECT 1 FROM journal_comments comment
      WHERE comment.entry_kind = 'execution'
        AND comment.entry_id = execution.id
        AND comment.deleted_at IS NULL
    )
    """)

    alter table(:workout_executions) do
      remove :exercise_notes
      remove :exercise_modifications
    end

    alter table(:training_log_entries) do
      remove :notes
      remove :exercise_modifications
    end

    execute("""
    UPDATE training_log_entries
    SET performed_exercises = ARRAY(
      SELECT row - 'note' FROM unnest(performed_exercises) AS row
    )
    WHERE EXISTS (SELECT 1 FROM unnest(performed_exercises) AS row WHERE row ? 'note')
    """)

    alter table(:user_pr_records) do
      remove :notes
    end

    alter table(:user_pr_history) do
      remove :notes
    end
  end

  def down do
    alter table(:user_pr_history) do
      add :notes, :text
    end

    alter table(:user_pr_records) do
      add :notes, :text
    end

    alter table(:training_log_entries) do
      add :notes, :text
      add :exercise_modifications, {:array, :map}, null: false, default: []
    end

    alter table(:workout_executions) do
      add :exercise_notes, {:array, :map}, null: false, default: []
      add :exercise_modifications, {:array, :map}, null: false, default: []
    end

    recreate_coaching_aggregates("cardinality(execution.exercise_notes) > 0")

    execute("DROP FUNCTION IF EXISTS milos_journal_entry_rung(text, uuid) CASCADE")
    execute("DROP FUNCTION IF EXISTS milos_journal_entry_owner(text, uuid) CASCADE")
    drop table(:journal_comments)
  end

  # Comments carry the owner and gym of their entry; ids of old notes are
  # kept when they are UUIDs, so clients that still hold them stay in step.
  defp migrate_execution_notes do
    execute("""
    INSERT INTO journal_comments (
      id, user_id, organization_id, entry_kind, entry_id, exercise_id, selected_text,
      selection_start, selection_end, tags, body, written_at, inserted_at, updated_at
    )
    SELECT
      CASE WHEN note->>'id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           THEN (note->>'id')::uuid ELSE gen_random_uuid() END,
      execution.user_id, execution.organization_id, 'execution', execution.id,
      note->>'exercise_id',
      NULLIF(btrim(COALESCE(note->>'selected_text', note->>'word')), ''),
      CASE WHEN (note->>'selection_end')::int > (note->>'selection_start')::int
           THEN (note->>'selection_start')::int END,
      CASE WHEN (note->>'selection_end')::int > (note->>'selection_start')::int
           THEN (note->>'selection_end')::int END,
      COALESCE(ARRAY(SELECT jsonb_array_elements_text(
        CASE WHEN jsonb_typeof(note->'tags') = 'array' THEN note->'tags' ELSE '[]'::jsonb END
      )), '{}'),
      NULLIF(left(btrim(note->>'note_text'), 4000), ''),
      COALESCE((note->>'inserted_at')::timestamptz, COALESCE(execution.completed_at_utc, execution.started_at_utc, execution.inserted_at)),
      COALESCE((note->>'inserted_at')::timestamptz, COALESCE(execution.completed_at_utc, execution.started_at_utc, execution.inserted_at)),
      COALESCE((note->>'updated_at')::timestamptz, COALESCE(execution.completed_at_utc, execution.started_at_utc, execution.inserted_at))
    FROM workout_executions execution, unnest(execution.exercise_notes) AS note
    WHERE NULLIF(btrim(note->>'note_text'), '') IS NOT NULL
       OR jsonb_array_length(
            CASE WHEN jsonb_typeof(note->'tags') = 'array' THEN note->'tags' ELSE '[]'::jsonb END
          ) > 0
    ON CONFLICT (id) DO NOTHING
    """)
  end

  # A free-text modification ("free_text" section, field "note") is plain
  # text on the whole entry; every other patch is a structured change keyed
  # by its patch id, with its own note as the comment's text.
  defp migrate_modifications(kind, table, fallback_time) do
    execute("""
    INSERT INTO journal_comments (
      id, user_id, organization_id, entry_kind, entry_id, section_id, exercise_id,
      body, change, change_key, written_at, inserted_at, updated_at
    )
    SELECT
      gen_random_uuid(), entry.user_id, entry.organization_id, '#{kind}', entry.id,
      CASE WHEN patch->>'section_id' = 'free_text' THEN NULL ELSE patch->>'section_id' END,
      patch->>'exercise_id',
      NULLIF(left(btrim(COALESCE(
        CASE WHEN patch->>'section_id' = 'free_text' THEN patch->>'actual_value' END,
        patch->>'note'
      )), 4000), ''),
      CASE WHEN patch->>'section_id' = 'free_text' THEN NULL
           ELSE patch - 'note' - 'logged_at' END,
      CASE WHEN patch->>'section_id' = 'free_text' THEN NULL ELSE patch->>'patch_id' END,
      COALESCE((patch->>'logged_at')::timestamptz, entry.#{fallback_time}),
      COALESCE((patch->>'logged_at')::timestamptz, entry.#{fallback_time}),
      COALESCE((patch->>'logged_at')::timestamptz, entry.#{fallback_time})
    FROM #{table} entry, unnest(entry.exercise_modifications) AS patch
    WHERE patch->>'section_id' <> 'free_text'
       OR NULLIF(btrim(COALESCE(patch->>'actual_value', patch->>'note')), '') IS NOT NULL
    ON CONFLICT DO NOTHING
    """)
  end

  defp migrate_training_log_text do
    execute("""
    INSERT INTO journal_comments (
      id, user_id, organization_id, entry_kind, entry_id, body, written_at, inserted_at, updated_at
    )
    SELECT gen_random_uuid(), entry.user_id, entry.organization_id, 'training_log', entry.id,
           left(btrim(entry.notes), 4000), entry.performed_at_utc, entry.inserted_at, entry.updated_at
    FROM training_log_entries entry
    WHERE NULLIF(btrim(entry.notes), '') IS NOT NULL
    """)

    execute("""
    INSERT INTO journal_comments (
      id, user_id, organization_id, entry_kind, entry_id, exercise_id, body,
      written_at, inserted_at, updated_at
    )
    SELECT gen_random_uuid(), entry.user_id, entry.organization_id, 'training_log', entry.id,
           'row:' || COALESCE(row->>'row_index', '0'), left(btrim(row->>'note'), 4000),
           entry.performed_at_utc, entry.inserted_at, entry.updated_at
    FROM training_log_entries entry, unnest(entry.performed_exercises) AS row
    WHERE NULLIF(btrim(row->>'note'), '') IS NOT NULL
    """)
  end

  defp migrate_pr_notes do
    execute("""
    INSERT INTO journal_comments (
      id, user_id, organization_id, entry_kind, entry_id, body, written_at, inserted_at, updated_at
    )
    SELECT gen_random_uuid(), record.user_id, record.organization_id, 'pr', record.id,
           left(btrim(source.notes), 4000), source.at, source.at, source.at
    FROM user_pr_records record
    JOIN LATERAL (
      SELECT DISTINCT ON (btrim(notes)) notes, at FROM (
        SELECT history.notes, history.inserted_at AS at
        FROM user_pr_history history WHERE history.pr_record_id = record.id
        UNION ALL
        SELECT record.notes, record.updated_at
      ) all_notes
      WHERE NULLIF(btrim(notes), '') IS NOT NULL
      ORDER BY btrim(notes), at
    ) source ON true
    """)
  end

  defp recreate_coaching_aggregates(note_predicate) do
    execute("DROP MATERIALIZED VIEW IF EXISTS coaching_aggregates")

    execute("""
    CREATE MATERIALIZED VIEW coaching_aggregates AS
    SELECT
      membership.organization_id,
      date_trunc('week', timezone('utc', NOW()))::date AS period_start,
      COUNT(DISTINCT membership.user_id) FILTER (
        WHERE EXISTS (
          SELECT 1
          FROM workout_executions recent_execution
          WHERE recent_execution.user_id = membership.user_id
            AND recent_execution.organization_id = membership.organization_id
            AND recent_execution.completed_at_utc >= timezone('utc', NOW()) - INTERVAL '14 days'
        )
      )::integer AS active_athlete_count,
      COUNT(DISTINCT membership.user_id) FILTER (
        WHERE NOT EXISTS (
          SELECT 1
          FROM workout_executions recent_execution
          WHERE recent_execution.user_id = membership.user_id
            AND recent_execution.organization_id = membership.organization_id
            AND recent_execution.completed_at_utc >= timezone('utc', NOW()) - INTERVAL '14 days'
        )
      )::integer AS inactive_athlete_count,
      COUNT(DISTINCT execution.id) FILTER (
        WHERE execution.completed_at_utc >= date_trunc('week', timezone('utc', NOW()))
      )::integer AS completed_workouts_this_week,
      COUNT(DISTINCT message.id) FILTER (
        WHERE message.inserted_at >= date_trunc('week', timezone('utc', NOW()))
      )::integer AS coach_notes_this_week,
      COALESCE(
        COUNT(DISTINCT execution.id) FILTER (
          WHERE execution.completed_at_utc >= date_trunc('week', timezone('utc', NOW()))
        )::float / NULLIF(COUNT(DISTINCT membership.user_id), 0)::float,
        0.0
      ) AS average_completion_rate,
      COUNT(DISTINCT execution.id) FILTER (
        WHERE #{note_predicate}
          AND execution.completed_at_utc >= timezone('utc', NOW()) - INTERVAL '30 days'
      )::integer AS recent_workout_note_count
    FROM organization_memberships membership
    JOIN organizations organization ON organization.id = membership.organization_id
    LEFT JOIN workout_executions execution
      ON execution.user_id = membership.user_id
      AND execution.organization_id = membership.organization_id
    LEFT JOIN messaging_messages message
      ON message.organization_id = membership.organization_id
      AND message.message_type = 'coaching_note'
    WHERE membership.status = 'active'
      AND membership.role = 'athlete'
      AND organization.status = 'active'
    GROUP BY membership.organization_id
    """)

    execute(
      "CREATE UNIQUE INDEX coaching_aggregates_organization_period_index " <>
        "ON coaching_aggregates (organization_id, period_start)"
    )
  end
end
