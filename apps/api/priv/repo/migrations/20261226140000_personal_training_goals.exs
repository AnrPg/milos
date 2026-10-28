defmodule Palee.Repo.Migrations.PersonalTrainingGoals do
  @moduledoc """
  ADR-222: the weekly workout goal belongs to the person, not the box.

  1. `training_goals`: one row per person and goal kind (today only
     `weekly_workouts`), kept only once someone set it, so no row means the
     platform default. `set_by_id`/`set_by_role` say who set it last (the
     person, their coach, or the box's staff) and `set_in_organization_id`
     in which box, so the member sees "set by your coach" and staff see who
     changed it.

     Personal data, read and written by the person and, inside a box, by
     the staff who may coach them. `palee_training_goal_reachable` is the
     database's coarse bound: the acting person themselves, or inside the
     session's box an owner/admin of that box (the goal's person an active
     member there), a head coach of that box (`coach_scope = 'all'`, the
     person an active member there), or a coach with an active coaching
     relationship with the person there. The application narrows staff further (ADR-099/100
     capability scopes).

  2. `gamification_settings` keeps only box-wide streak rules: the new
     `streak_shields` (how many shields each member gets per renewal, 0-5,
     1 as before) next to the existing `streak_shield_reset_day`. The box
     weekly target is dropped: the app is unreleased and no box relies on it.

  3. Notification type `training_goal_updated`: someone else changed the
     person's goal.
  """

  use Ecto.Migration

  @notification_types ~w(training_goal_updated)

  def up do
    create table(:training_goals, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :kind, :string, null: false
      add :target, :integer, null: false
      add :set_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :set_by_role, :string, null: false

      add :set_in_organization_id,
          references(:organizations, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:training_goals, [:user_id, :kind])

    create constraint(:training_goals, :training_goals_shape_check,
             check: """
             kind IN ('weekly_workouts')
             AND target BETWEEN 1 AND 14
             AND set_by_role IN ('self', 'coach', 'staff')
             """
           )

    execute("""
    CREATE OR REPLACE FUNCTION palee_training_goal_reachable(member_id uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      WITH acting AS (
        SELECT
          NULLIF(current_setting('app.user_id', true), '')::uuid AS user_id,
          NULLIF(current_setting('app.organization_id', true), '')::uuid AS organization_id
      )
      SELECT
        member_id = acting.user_id
        OR (
          acting.organization_id IS NOT NULL
          AND (
            EXISTS (
              SELECT 1
              FROM public.coaching_relationships cr
              WHERE cr.organization_id = acting.organization_id
                AND cr.coach_user_id = acting.user_id
                AND cr.client_user_id = member_id
                AND cr.ended_at IS NULL
            )
            OR (
              EXISTS (
                SELECT 1
                FROM public.organization_memberships staff
                WHERE staff.organization_id = acting.organization_id
                  AND staff.user_id = acting.user_id
                  AND staff.status = 'active'
                  AND (
                    staff.roles && ARRAY['owner', 'admin']::varchar[]
                    OR ('coach' = ANY (staff.roles) AND staff.coach_scope = 'all')
                  )
              )
              AND EXISTS (
                SELECT 1
                FROM public.organization_memberships client
                WHERE client.organization_id = acting.organization_id
                  AND client.user_id = member_id
                  AND client.status = 'active'
              )
            )
          )
        )
      FROM acting
    $$
    """)

    execute("""
    CREATE POLICY training_goals_person_or_coach_policy ON training_goals
    USING (palee_training_goal_reachable(user_id))
    WITH CHECK (palee_training_goal_reachable(user_id))
    """)

    execute("ALTER TABLE training_goals ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE training_goals FORCE ROW LEVEL SECURITY")

    alter table(:gamification_settings) do
      add :streak_shields, :integer, null: false, default: 1
      remove :weekly_workout_target
    end

    create constraint(:gamification_settings, :gamification_settings_streak_shields_check,
             check: "streak_shields BETWEEN 0 AND 5"
           )

    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    drop constraint(:gamification_settings, :gamification_settings_streak_shields_check)

    alter table(:gamification_settings) do
      remove :streak_shields
      add :weekly_workout_target, :integer, null: false, default: 2
    end

    execute("DROP POLICY IF EXISTS training_goals_person_or_coach_policy ON training_goals")
    drop table(:training_goals)
    execute("DROP FUNCTION IF EXISTS palee_training_goal_reachable(uuid)")
  end

  defp add_notification_types(types), do: rewrite_notification_types(&Enum.uniq(&1 ++ types))
  defp remove_notification_types(types), do: rewrite_notification_types(&(&1 -- types))

  # The same read-modify-write of notifications_type_check as earlier
  # migrations, so types other migrations added stay.
  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{in_list(change.(current))}))"
    )
  end

  defp in_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
