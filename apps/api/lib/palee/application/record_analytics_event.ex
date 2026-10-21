defmodule Palee.Application.RecordAnalyticsEvent do
  alias Palee.Analytics

  @telemetry_events %{
    "payment_recorded" => [:palee, :payment, :recorded],
    "promotion_redeemed" => [:palee, :promotion, :redeemed],
    "referral_event_created" => [:palee, :referral, :created],
    "referral_status_changed" => [:palee, :referral, :status_changed],
    "referral_reward_created" => [:palee, :referral, :reward_created],
    "referral_reward_status_changed" => [:palee, :referral, :reward_status_changed],
    "review_submitted" => [:palee, :review, :submitted],
    "injury_reported" => [:palee, :injury, :reported],
    "injury_healed" => [:palee, :injury, :healed],
    "notification_read" => [:palee, :notification, :read],
    "notification_clicked" => [:palee, :notification, :clicked]
  }

  def call(event_name, attrs \\ %{}) when is_binary(event_name) and is_map(attrs) do
    params =
      attrs
      |> string_key_map()
      |> Map.put("event_name", event_name)

    :telemetry.execute(telemetry_event(event_name), %{count: 1}, params)

    case record(params) do
      {:ok, _event_or_duplicate} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def call_unsafe(event_name, attrs \\ %{}) do
    case call(event_name, attrs) do
      :ok ->
        :ok

      {:error, reason} ->
        report_failure(event_name, reason)
        :ok
    end
  rescue
    # Analytics is a best-effort side effect: a DB-level failure recording it
    # (e.g. no tenant context available to satisfy analytics_events'
    # organization_id) must never take down the caller's primary action.
    error ->
      report_failure(event_name, error.__struct__)
      :ok
  end

  # ADR-123: when the caller names the tenant explicitly, record inside that
  # tenant's session so the row satisfies the forced RLS policy even when the
  # surrounding code runs under a user-only or job session (executions,
  # notification jobs). Without an explicit organization the surrounding
  # session's tenant is used, as before.
  defp record(%{"organization_id" => organization_id} = params)
       when is_binary(organization_id) do
    Analytics.with_tenant_context(%{organization_id: organization_id}, fn ->
      Analytics.record_event(params)
    end)
  end

  defp record(params), do: Analytics.record_event(params)

  defp report_failure(event_name, reason) do
    :telemetry.execute([:palee, :analytics, :record_failed], %{count: 1}, %{
      event_name: event_name,
      reason: inspect(reason)
    })
  end

  defp telemetry_event(event_name),
    do: Map.get(@telemetry_events, event_name, [:palee, :analytics, :event_recorded])

  defp string_key_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
