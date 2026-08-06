defmodule MilosTraining.Repo.Migrations.AddOrganizationIdToUserAchievements do
  use Ecto.Migration

  def up do
    alter table(:user_achievements) do
      add(:organization_id, :binary_id)
    end

    # Best-effort backfill for existing rows (all created before this column
    # existed). PR-event badges embed the source execution id in their
    # badge_key ("pr_event:<execution_id>:<section_id>"), so those can be
    # backfilled precisely via the execution's own organization_id. Every
    # other badge (milestones, challenge badges) falls back to the user's
    # earliest active organization membership - correct today since
    # production is single-tenant, and a reasonable best guess otherwise.
    execute("""
    UPDATE user_achievements ua
    SET organization_id = we.organization_id
    FROM workout_executions we
    WHERE ua.organization_id IS NULL
      AND ua.badge_key LIKE 'pr_event:%'
      AND we.id = NULLIF(split_part(ua.badge_key, ':', 2), '')::uuid
    """)

    execute("""
    UPDATE user_achievements ua
    SET organization_id = om.organization_id
    FROM (
      SELECT DISTINCT ON (user_id) user_id, organization_id
      FROM organization_memberships
      WHERE status = 'active'
      ORDER BY user_id, joined_at ASC
    ) om
    WHERE ua.organization_id IS NULL
      AND om.user_id = ua.user_id
    """)

    execute("""
    CREATE INDEX user_achievements_organization_id_index
    ON user_achievements (organization_id)
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS user_achievements_organization_id_index")

    alter table(:user_achievements) do
      remove(:organization_id)
    end
  end
end
