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
