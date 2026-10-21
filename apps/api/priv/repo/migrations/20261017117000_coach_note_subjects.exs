defmodule Palee.Repo.Migrations.CoachNoteSubjects do
  @moduledoc """
  ADR-140 §5: a coach note may be about one thing of the client's (an
  execution, a training log, a PR, an injury, a form review or an assigned
  workout). The subject must be the client's and, when it belongs to a gym,
  the note's gym (personal entries reach coaches through the ladder); a
  trigger checks it because the subject lives in another context's table.
  """

  use Ecto.Migration

  @kinds ~w(execution training_log pr injury form_review assignment)

  def up do
    alter table(:coaching_notes) do
      add :subject_kind, :string
      add :subject_id, :binary_id
    end

    kinds = Enum.map_join(@kinds, ", ", &"'#{&1}'")

    create constraint(:coaching_notes, :coaching_notes_subject_check,
             check:
               "(subject_kind IS NULL AND subject_id IS NULL) OR " <>
                 "(subject_kind IN (#{kinds}) AND subject_id IS NOT NULL)"
           )

    create index(:coaching_notes, [:organization_id, :subject_kind, :subject_id],
             where: "subject_id IS NOT NULL"
           )

    execute("""
    CREATE OR REPLACE FUNCTION palee_coach_note_subject_belongs(
      kind text, subject uuid, client uuid, organization uuid
    )
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT CASE kind
        WHEN 'execution' THEN EXISTS (
          SELECT 1 FROM workout_executions e
          WHERE e.id = subject AND e.user_id = client 
            AND (e.organization_id IS NULL OR e.organization_id = organization))
        WHEN 'training_log' THEN EXISTS (
          SELECT 1 FROM training_log_entries l
          WHERE l.id = subject AND l.user_id = client AND l.organization_id = organization)
        WHEN 'pr' THEN EXISTS (
          SELECT 1 FROM user_pr_records p
          WHERE p.id = subject AND p.user_id = client 
            AND (p.organization_id IS NULL OR p.organization_id = organization))
        WHEN 'injury' THEN EXISTS (
          SELECT 1 FROM injury_reports i
          WHERE i.id = subject AND i.user_id = client 
            AND (i.organization_id IS NULL OR i.organization_id = organization))
        WHEN 'form_review' THEN EXISTS (
          SELECT 1 FROM coaching_form_reviews r
          WHERE r.id = subject AND r.user_id = client AND r.organization_id = organization)
        WHEN 'assignment' THEN EXISTS (
          SELECT 1 FROM assigned_workout_athletes a
          WHERE a.assigned_workout_id = subject AND a.athlete_id = client
            AND a.organization_id = organization)
        ELSE false
      END
    $$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_coaching_notes_check_subject()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.subject_id IS NOT NULL AND NOT palee_coach_note_subject_belongs(
        NEW.subject_kind, NEW.subject_id, NEW.client_user_id, NEW.organization_id
      ) THEN
        RAISE EXCEPTION 'coach note subject is not the client''s'
          USING ERRCODE = 'check_violation', CONSTRAINT = 'coaching_notes_subject_owner_check';
      END IF;
      RETURN NEW;
    END
    $$
    """)

    execute("""
    CREATE TRIGGER coaching_notes_check_subject
    BEFORE INSERT OR UPDATE OF subject_kind, subject_id, client_user_id ON coaching_notes
    FOR EACH ROW EXECUTE FUNCTION palee_coaching_notes_check_subject()
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS coaching_notes_check_subject ON coaching_notes")
    execute("DROP FUNCTION IF EXISTS palee_coaching_notes_check_subject()")
    execute("DROP FUNCTION IF EXISTS palee_coach_note_subject_belongs(text, uuid, uuid, uuid)")

    alter table(:coaching_notes) do
      remove :subject_kind
      remove :subject_id
    end
  end
end
