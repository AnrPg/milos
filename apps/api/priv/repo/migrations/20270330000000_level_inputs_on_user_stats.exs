defmodule Palee.Repo.Migrations.LevelInputsOnUserStats do
  @moduledoc """
  ADR-285: «Επίπεδο» is worked out from the person's stats (`Domain.Level`),
  so the stats carry the two facts it needs that they did not hold yet:

  * `weeks_on_goal`: every week (user-relative, ADR-229) that reached the
    person's weekly goal, refreshed by each completion projection.
  * `challenges_completed`: challenges the person finished, counted from
    their progress rows here and incremented when the projection completes
    one.

  `motivation_score` («Κίνητρο») is no longer written or read: it repeated
  the Συνέπεια card. The column stays until every running release has
  stopped selecting it (TD-285), so a rolling deploy never fails a read.
  """

  use Ecto.Migration

  def up do
    alter table(:user_stats) do
      add :weeks_on_goal, :integer, null: false, default: 0
      add :challenges_completed, :integer, null: false, default: 0
    end

    create constraint(:user_stats, :user_stats_weeks_on_goal_non_negative,
             check: "weeks_on_goal >= 0"
           )

    create constraint(:user_stats, :user_stats_challenges_completed_non_negative,
             check: "challenges_completed >= 0"
           )

    execute("""
    UPDATE user_stats AS stats
    SET challenges_completed = done.total
    FROM (
      SELECT user_id, count(*)::integer AS total
      FROM user_challenge_progress
      WHERE completed_at IS NOT NULL
      GROUP BY user_id
    ) AS done
    WHERE done.user_id = stats.user_id
    """)
  end

  def down do
    drop constraint(:user_stats, :user_stats_challenges_completed_non_negative)
    drop constraint(:user_stats, :user_stats_weeks_on_goal_non_negative)

    alter table(:user_stats) do
      remove :challenges_completed
      remove :weeks_on_goal
    end
  end
end
