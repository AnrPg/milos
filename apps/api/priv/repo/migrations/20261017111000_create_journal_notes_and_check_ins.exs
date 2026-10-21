defmodule Palee.Repo.Migrations.CreateJournalNotesAndCheckIns do
  @moduledoc """
  ADR-139: the two private-by-default journal entries (Σημείωση; Πώς νιώθω,
  the short questionnaire of ADR-140 §2),
  the audit of coach reads of journal entries, and the journal entry a
  "Ζητάω απάντηση" message is about.

  Notes and check-ins are personal data with gym provenance (the gym the
  member wrote them in), like Pantheon PRs (ADR-129): the owner reads and
  writes them in any session; a coach of the provenance gym reads them only
  while their rung reaches the coach (`palee_entry_visible_to_acting_coach`).
  """

  use Ecto.Migration

  @member_rungs "('private', 'coach_can_view', 'coach_reply_requested', 'posted')"

  def change do
    create table(:journal_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all)

      add :topic, :string, null: false
      add :body, :text, null: false
      add :linked_kind, :string
      add :linked_id, :binary_id
      add :written_at, :utc_datetime_usec, null: false
      add :written_tz, :string, null: false, default: "UTC"
      add :journal_visibility, :string, null: false, default: "private"
      add :deleted_at, :utc_datetime_usec
      add :lock_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:journal_notes, :journal_notes_topic_check,
             check: "topic IN ('technique', 'thought', 'mood', 'goal')"
           )

    create constraint(:journal_notes, :journal_notes_link_check,
             check:
               "(linked_kind IS NULL AND linked_id IS NULL) OR " <>
                 "(linked_kind IN ('execution', 'training_log', 'workout') AND linked_id IS NOT NULL)"
           )

    create constraint(:journal_notes, :journal_notes_body_check,
             check: "char_length(body) BETWEEN 1 AND 4000"
           )

    create constraint(:journal_notes, :journal_notes_journal_visibility_check,
             check: "journal_visibility IN #{@member_rungs}"
           )

    create index(:journal_notes, [:user_id, :written_at], where: "deleted_at IS NULL")
    create index(:journal_notes, [:organization_id])

    # Πώς νιώθω (ADR-140 §2): every submission is an immutable, timestamped
    # row; a member may submit many times a day and the latest is the current
    # state. Answers are one row per question of the catalog in code.
    create table(:wellbeing_check_ins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all)

      add :recorded_at, :utc_datetime_usec, null: false
      add :recorded_tz, :string, null: false, default: "UTC"
      add :journal_visibility, :string, null: false, default: "private"
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:wellbeing_check_ins, :wellbeing_check_ins_journal_visibility_check,
             check: "journal_visibility IN #{@member_rungs}"
           )

    create index(:wellbeing_check_ins, [:user_id, :recorded_at], where: "deleted_at IS NULL")
    create index(:wellbeing_check_ins, [:organization_id])

    create table(:wellbeing_check_in_answers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :check_in_id,
          references(:wellbeing_check_ins, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :question_key, :string, null: false
      add :value, :smallint, null: false
      add :note, :text

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:wellbeing_check_in_answers, :wellbeing_check_in_answers_value_check,
             check: "value BETWEEN 1 AND 4"
           )

    create constraint(:wellbeing_check_in_answers, :wellbeing_check_in_answers_note_check,
             check: "note IS NULL OR char_length(note) BETWEEN 1 AND 1000"
           )

    create unique_index(:wellbeing_check_in_answers, [:check_in_id, :question_key])
    create index(:wellbeing_check_in_answers, [:user_id, :question_key])

    # The owner writes answers; anyone who may read the check-in (its owner,
    # or a coach its rung reaches) may read them, through the parent's RLS.
    execute(
      """
      CREATE POLICY wellbeing_check_in_answers_owner_policy ON wellbeing_check_in_answers
      USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS wellbeing_check_in_answers_owner_policy ON wellbeing_check_in_answers"
    )

    execute(
      """
      CREATE POLICY wellbeing_check_in_answers_read_policy ON wellbeing_check_in_answers
      FOR SELECT
      USING (EXISTS (SELECT 1 FROM wellbeing_check_ins c WHERE c.id = check_in_id))
      """,
      "DROP POLICY IF EXISTS wellbeing_check_in_answers_read_policy ON wellbeing_check_in_answers"
    )

    execute(
      "ALTER TABLE wellbeing_check_in_answers ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE wellbeing_check_in_answers DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE wellbeing_check_in_answers FORCE ROW LEVEL SECURITY",
      "ALTER TABLE wellbeing_check_in_answers NO FORCE ROW LEVEL SECURITY"
    )

    for table <- ~w(journal_notes wellbeing_check_ins) do
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
          AND palee_entry_visible_to_acting_coach(user_id, organization_id, journal_visibility)
        )
        """,
        "DROP POLICY IF EXISTS #{table}_coach_read_policy ON #{table}"
      )

      execute(
        "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY",
        "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
      )

      execute(
        "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY",
        "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
      )
    end

    # One row per journal entry a coach was shown (ADR-101 pattern).
    create table(:journal_coach_reads, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :reader_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :owner_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :entry_kind, :string, null: false
      add :entry_id, :binary_id, null: false
      add :read_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:journal_coach_reads, [:organization_id, :owner_user_id, :read_at])

    execute(
      """
      CREATE TRIGGER journal_coach_reads_apply_tenant_context
      BEFORE INSERT OR UPDATE ON journal_coach_reads
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """,
      "DROP TRIGGER IF EXISTS journal_coach_reads_apply_tenant_context ON journal_coach_reads"
    )

    execute(
      """
      CREATE POLICY journal_coach_reads_tenant_policy ON journal_coach_reads
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS journal_coach_reads_tenant_policy ON journal_coach_reads"
    )

    execute(
      "ALTER TABLE journal_coach_reads ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE journal_coach_reads DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE journal_coach_reads FORCE ROW LEVEL SECURITY",
      "ALTER TABLE journal_coach_reads NO FORCE ROW LEVEL SECURITY"
    )

    # A "Ζητάω απάντηση" message names the journal entry it asks about.
    alter table(:messaging_messages) do
      add :subject_kind, :string
      add :subject_id, :binary_id
    end

    create constraint(:messaging_messages, :messaging_messages_subject_check,
             check:
               "(subject_kind IS NULL AND subject_id IS NULL) OR " <>
                 "(subject_kind IN ('execution', 'training_log', 'pr', 'injury', 'note', 'check_in') " <>
                 "AND subject_id IS NOT NULL)"
           )
  end
end
