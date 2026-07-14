defmodule MilosTraining.Application.RecordAnalyticsEvent do
  alias MilosTraining.Analytics

  @telemetry_events %{
    "payment_recorded" => [:milos, :payment, :recorded],
    "promotion_redeemed" => [:milos, :promotion, :redeemed],
    "referral_event_created" => [:milos, :referral, :created],
    "referral_status_changed" => [:milos, :referral, :status_changed],
    "referral_reward_created" => [:milos, :referral, :reward_created],
    "referral_reward_status_changed" => [:milos, :referral, :reward_status_changed],
    "review_submitted" => [:milos, :review, :submitted],
    "injury_reported" => [:milos, :injury, :reported],
    "injury_healed" => [:milos, :injury, :healed],
    "notification_read" => [:milos, :notification, :read],
    "notification_clicked" => [:milos, :notification, :clicked]
  }

  def call(event_name, attrs \\ %{}) when is_binary(event_name) and is_map(attrs) do
    params =
      attrs
      |> string_key_map()
      |> Map.put("event_name", event_name)

    :telemetry.execute(telemetry_event(event_name), %{count: 1}, params)

    case Analytics.record_event(params) do
      {:ok, _event} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def call_unsafe(event_name, attrs \\ %{}) do
    case call(event_name, attrs) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp telemetry_event(event_name),
    do: Map.get(@telemetry_events, event_name, [:milos, :analytics, :event_recorded])

  defp string_key_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
