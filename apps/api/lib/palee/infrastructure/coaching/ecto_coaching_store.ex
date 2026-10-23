defmodule Palee.Infrastructure.Coaching.EctoCoachingStore do
  @behaviour Palee.Coaching.Ports.CoachingStore

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @impl true
  def get_aggregates do
    with organization_id when is_binary(organization_id) <-
           RepoContext.current_setting("app.organization_id"),
         {:ok, result} <-
           Repo.query(
             """
             SELECT period_start, active_athlete_count, inactive_athlete_count,
                    completed_workouts_this_week, coaching_messages_this_week,
                    average_completion_rate, awaiting_reply_count
             FROM coaching_aggregates
             WHERE organization_id = $1::uuid
             ORDER BY period_start DESC
             LIMIT 1
             """,
             [Ecto.UUID.dump!(organization_id)]
           ) do
      case result do
        %{rows: [[period_start, active, inactive, completed, messages, rate, awaiting]]} ->
          %{
            period_start: period_start,
            active_athlete_count: active,
            inactive_athlete_count: inactive,
            completed_workouts_this_week: completed,
            coaching_messages_this_week: messages,
            average_completion_rate: rate,
            awaiting_reply_count: awaiting,
            aggregate_status: "available"
          }

        %{rows: []} ->
          empty_aggregates("available", nil)
      end
    else
      _missing_scope -> empty_aggregates("unavailable", "missing_organization_scope")
    end
  end

  # ADR-186 §7: the same figures as `coaching_aggregates`, live, for the
  # athletes among `user_ids` (the people of the filtered branches).
  @impl true
  def get_aggregates_for_users(user_ids) do
    with organization_id when is_binary(organization_id) <-
           RepoContext.current_setting("app.organization_id"),
         {:ok, %{rows: [[active, inactive, completed, messages, rate, awaiting]]}} <-
           Repo.query(
             """
             WITH athletes AS (
               SELECT DISTINCT membership.user_id
               FROM organization_memberships membership
               WHERE membership.organization_id = $1::uuid
                 AND membership.status = 'active'
                 AND membership.role = 'athlete'
                 AND membership.user_id = ANY($2::uuid[])
             ), recent AS (
               SELECT athlete.user_id,
                      EXISTS (
                        SELECT 1 FROM workout_executions execution
                        WHERE execution.user_id = athlete.user_id
                          AND execution.organization_id = $1::uuid
                          AND execution.completed_at_utc >= timezone('utc', NOW()) - INTERVAL '14 days'
                      ) AS active
               FROM athletes athlete
             ), threads AS (
               SELECT DISTINCT participant.thread_id
               FROM messaging_participants participant
               WHERE participant.user_id = ANY($2::uuid[])
             ), week_executions AS (
               SELECT COUNT(*)::integer AS total
               FROM workout_executions execution
               WHERE execution.organization_id = $1::uuid
                 AND execution.user_id IN (SELECT user_id FROM athletes)
                 AND execution.completed_at_utc >= date_trunc('week', timezone('utc', NOW()))
             )
             SELECT
               (SELECT COUNT(*) FROM recent WHERE active)::integer,
               (SELECT COUNT(*) FROM recent WHERE NOT active)::integer,
               (SELECT total FROM week_executions),
               (SELECT COUNT(*) FROM messaging_messages message
                WHERE message.organization_id = $1::uuid
                  AND message.message_type = 'coaching_message'
                  AND message.inserted_at >= date_trunc('week', timezone('utc', NOW()))
                  AND message.thread_id IN (SELECT thread_id FROM threads))::integer,
               COALESCE((SELECT total FROM week_executions)::float /
                 NULLIF((SELECT COUNT(*) FROM athletes), 0)::float, 0.0),
               (SELECT COUNT(*) FROM messaging_messages request
                WHERE request.organization_id = $1::uuid
                  AND request.subject_id IS NOT NULL
                  AND request.thread_id IN (SELECT thread_id FROM threads)
                  AND NOT EXISTS (
                    SELECT 1 FROM messaging_messages answer
                    WHERE answer.thread_id = request.thread_id
                      AND answer.sender_id <> request.sender_id
                      AND answer.sequence_number > request.sequence_number
                  ))::integer
             """,
             [Ecto.UUID.dump!(organization_id), Enum.map(user_ids, &Ecto.UUID.dump!/1)]
           ) do
      %{
        period_start: nil,
        active_athlete_count: active,
        inactive_athlete_count: inactive,
        completed_workouts_this_week: completed,
        coaching_messages_this_week: messages,
        average_completion_rate: rate,
        awaiting_reply_count: awaiting,
        aggregate_status: "available"
      }
    else
      _missing_scope -> empty_aggregates("unavailable", "missing_organization_scope")
    end
  end

  # TD-092: the runtime role does not own the view, so the refresh goes
  # through the allow-listed SECURITY DEFINER helper (ADR-131).
  @impl true
  def refresh_aggregates do
    case Repo.query("SELECT palee_refresh_materialized_view($1)", ["coaching_aggregates"]) do
      {:ok, _result} -> :ok
      {:error, %Postgrex.Error{postgres: %{message: message}}} -> {:error, message}
      {:error, reason} -> {:error, reason}
    end
  end

  defp empty_aggregates(status, error) do
    %{
      period_start: nil,
      active_athlete_count: 0,
      inactive_athlete_count: 0,
      completed_workouts_this_week: 0,
      coaching_messages_this_week: 0,
      average_completion_rate: 0.0,
      awaiting_reply_count: 0,
      aggregate_status: status,
      aggregate_error: error
    }
  end
end
