defmodule MilosTraining.Repo.Migrations.CreateUserInsights do
  @moduledoc """
  ADR-166 (P3-M4, Πρόοδος › Insights): one row per person and insight rule,
  written by the nightly job (and on read when the rows are older than a
  day).

  - `status`: `finding` (enough data and a clear pattern), `no_finding`
    (enough data, nothing clear), `insufficient` (not enough data yet) or
    `off` (the journal section or wellness item the rule reads is switched
    off; nothing about it is kept).
  - `value`: the finding's numbers for the client copy (`variant`,
    `params`, `weeks` of data, sample sizes); for `insufficient` only the
    weeks of data so far.
  - `fingerprint`: the qualitative finding (rule, variant and the named
    part of day or trigger, never the numbers). A dismissal stores the
    fingerprint it hid, so the insight stays hidden until the finding
    itself changes.

  Insights are derived from the person's own private data: owner-only rows
  (no coach policy), deleted with the account. The nightly job finds whom to
  compute through a definer lookup that answers user ids only, and then
  works in each person's own session.
  """

  use Ecto.Migration

  @statuses "('finding', 'no_finding', 'insufficient', 'off')"

  def up do
    create table(:user_insights, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :rule, :string, null: false
      add :status, :string, null: false
      add :period_start, :date, null: false
      add :period_end, :date, null: false
      add :value, :map, null: false, default: %{}
      add :fingerprint, :string
      add :computed_at, :utc_datetime_usec, null: false
      add :dismissed_fingerprint, :string
      add :dismissed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_insights, [:user_id, :rule])

    create constraint(:user_insights, :user_insights_status_check,
             check: "status IN #{@statuses}"
           )

    create constraint(:user_insights, :user_insights_value_check,
             check: "jsonb_typeof(value) = 'object'"
           )

    create constraint(:user_insights, :user_insights_period_check,
             check: "period_start <= period_end"
           )

    execute("""
    CREATE POLICY user_insights_owner_policy ON user_insights
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("ALTER TABLE user_insights ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE user_insights FORCE ROW LEVEL SECURITY")

    # People with anything an insight reads since `p_since`: a training
    # session, a wellness entry or a craving. Keyset on the id; ids only.
    execute("""
    CREATE FUNCTION milos_insight_candidates(p_since timestamp, p_after uuid, p_lim integer)
    RETURNS SETOF uuid
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT DISTINCT candidate.user_id
      FROM (
        SELECT t.user_id FROM public.training_log_entries t
        WHERE t.performed_at_utc >= p_since AND t.status = 'logged'
        UNION
        SELECT e.user_id FROM public.workout_executions e
        WHERE e.completed_at_utc >= p_since
        UNION
        SELECT w.user_id FROM public.wellness_entries w
        WHERE w.occurred_at >= p_since AND w.deleted_at IS NULL
        UNION
        SELECT c.user_id FROM public.craving_entries c
        WHERE c.occurred_at >= p_since AND c.deleted_at IS NULL
      ) candidate
      WHERE candidate.user_id IS NOT NULL
        AND (p_after IS NULL OR candidate.user_id > p_after)
      ORDER BY candidate.user_id
      LIMIT p_lim
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS milos_insight_candidates(timestamp, uuid, integer)")
    drop table(:user_insights)
  end
end
