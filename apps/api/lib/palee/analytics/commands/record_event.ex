defmodule Palee.Analytics.Commands.RecordEvent do
  alias Palee.Analytics.AnalyticsStore
  alias Palee.Analytics.Domain.EventCatalog

  @doc """
  Records one analytics event after checking its name against the
  `EventCatalog` registry. Returns `{:ok, event}`, `{:ok, :duplicate}` when a
  row with the same dedupe key already exists in the tenant, or an error.
  """
  def call(params) do
    with :ok <- registered(params), do: AnalyticsStore.record_event(params)
  end

  @doc "Batch variant; every event name must be registered."
  def call_many(params_list) when is_list(params_list) do
    if Enum.all?(params_list, &(registered(&1) == :ok)),
      do: AnalyticsStore.record_events(params_list),
      else: {:error, :unknown_analytics_event}
  end

  defp registered(params) do
    name = Map.get(params, :event_name) || Map.get(params, "event_name")
    if EventCatalog.registered?(name), do: :ok, else: {:error, :unknown_analytics_event}
  end
end
