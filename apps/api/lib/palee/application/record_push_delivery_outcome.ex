defmodule Palee.Application.RecordPushDeliveryOutcome do
  @moduledoc """
  Records the outcome of one push dispatch attempt (ADR-123) from the push
  dispatch job, in the notification's tenant:

  * a `push_dispatch_attempts` fact row (status sent/expired/failed, the
    reason class in `error`, a SHA-256 of the endpoint instead of the URL), so
    the existing admin analytics summary reports real delivery numbers, and
  * a `notification_push_outcome` analytics event with outcome, reason class,
    notification type and attempt number.

  Attempts without tenant provenance are skipped. Never raises and always
  returns `:ok`, so analytics can't change the job's retry behaviour.
  """

  alias Palee.Application.TrackAnalyticsEvent
  alias Palee.{Analytics, Notifications}

  def call(args, result, attempt \\ 1, max_attempts \\ 1)

  def call(%{"organization_id" => organization_id} = args, result, attempt, max_attempts)
      when is_binary(organization_id) do
    {outcome, reason_class} = Notifications.classify_push_outcome(result)
    now = DateTime.utc_now()

    record_attempt(organization_id, args, outcome, reason_class, attempt, now)

    TrackAnalyticsEvent.call(
      "notification_push_outcome",
      nil,
      %{id: args["notification_id"]},
      %{
        organization_id: organization_id,
        user_id: args["user_id"],
        occurred_at: now,
        metadata: %{
          outcome: outcome,
          reason_class: reason_class,
          notification_type: args["type"],
          attempt: attempt,
          final_attempt: outcome != "failed" or attempt >= max_attempts
        }
      }
    )
  rescue
    _error -> :ok
  end

  def call(_args, _result, _attempt, _max_attempts), do: :ok

  defp record_attempt(organization_id, args, outcome, reason_class, attempt, now) do
    Analytics.with_tenant_context(%{organization_id: organization_id}, fn ->
      Analytics.record_push_attempt(%{
        organization_id: organization_id,
        notification_id: args["notification_id"],
        user_id: args["user_id"],
        endpoint_hash: endpoint_hash(args["endpoint"]),
        status: outcome,
        attempted_at: now,
        completed_at: now,
        error: reason_class,
        metadata: %{"notification_type" => args["type"], "attempt" => attempt}
      })
    end)
  rescue
    _error -> :ok
  end

  defp endpoint_hash(endpoint) when is_binary(endpoint),
    do: :sha256 |> :crypto.hash(endpoint) |> Base.encode16(case: :lower)

  defp endpoint_hash(_endpoint), do: "unknown"
end
