defmodule MilosTraining.Repo.Migrations.BackfillLegacyPrProvenance do
  @moduledoc """
  ADR-132 / TD-091: gives legacy Pantheon PRs (recorded before ADR-129 wrote
  provenance) the gym they were set in, where that gym is unambiguous.

  PR records carry no link to a source execution or workout (they are entered
  by hand), so the gym is inferred from the owner's own data, in this order:

  1. Execution evidence. The owner's workout executions that started within
     one day either side of the PR's `beaten_on` date (UTC; the window absorbs
     time zones) all belong to exactly one organization -> that organization.
  2. Membership evidence. There is no execution evidence at all, the owner has
     exactly one organization membership (any status), and it was joined no
     later than the PR was recorded -> that organization.

  Anything else (executions in two gyms that day, several memberships, a PR
  recorded before the only membership began) stays personal. History rows of
  a backfilled record take the record's provenance, as new snapshots do.

  Additive and idempotent: only rows whose `organization_id` is still NULL are
  touched, so re-running it (or running it after new PRs exist) changes
  nothing that already has provenance. `down` is a no-op: provenance written
  here is indistinguishable from provenance chosen by the owner afterwards.
  Runs as the migration role, which is not subject to the owner-only RLS
  policies on these personal tables.
  """

  use Ecto.Migration

  def up do
    execute("""
    WITH evidence AS (
      SELECT
        r.id,
        r.user_id,
        r.inserted_at,
        (
          SELECT array_agg(DISTINCT e.organization_id)
          FROM workout_executions e
          WHERE e.user_id = r.user_id
            AND e.organization_id IS NOT NULL
            AND e.started_at_utc >= (r.beaten_on - 1)::timestamp
            AND e.started_at_utc < (r.beaten_on + 2)::timestamp
        ) AS execution_orgs,
        (
          SELECT array_agg(m.organization_id)
          FROM organization_memberships m
          WHERE m.user_id = r.user_id
        ) AS membership_orgs
      FROM user_pr_records r
      WHERE r.organization_id IS NULL
    ),
    inferred AS (
      SELECT
        ev.id,
        CASE
          WHEN cardinality(ev.execution_orgs) = 1 THEN ev.execution_orgs[1]
          WHEN ev.execution_orgs IS NULL
               AND cardinality(ev.membership_orgs) = 1
               AND EXISTS (
                 SELECT 1
                 FROM organization_memberships m
                 WHERE m.user_id = ev.user_id
                   AND m.organization_id = ev.membership_orgs[1]
                   AND (m.joined_at IS NULL OR m.joined_at <= ev.inserted_at)
               )
            THEN ev.membership_orgs[1]
        END AS organization_id
      FROM evidence ev
    )
    UPDATE user_pr_records r
    SET organization_id = inferred.organization_id
    FROM inferred
    WHERE r.id = inferred.id
      AND r.organization_id IS NULL
      AND inferred.organization_id IS NOT NULL
    """)

    execute("""
    UPDATE user_pr_history h
    SET organization_id = r.organization_id
    FROM user_pr_records r
    WHERE h.pr_record_id = r.id
      AND h.organization_id IS NULL
      AND r.organization_id IS NOT NULL
    """)
  end

  def down, do: :ok
end
