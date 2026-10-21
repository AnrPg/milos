defmodule Palee.Application.DevicePresenter do
  @moduledoc "How devices, imports and watch workouts are shown (ADR-161)."

  alias Palee.Devices

  @doc """
  The Garmin row: `status` keeps the devices page's vocabulary
  (`unavailable` is «Σύντομα», when the server has no Garmin credentials),
  `connection` the details once there is one.
  """
  def garmin_row(connection, configured?) do
    live = live(connection)

    %{
      provider: "garmin",
      status: Devices.row_status(live, configured?),
      configured: configured?,
      capability: if(configured?, do: "available", else: "not_configured"),
      sync_prefs: (live && live.sync_prefs) || Devices.default_prefs(),
      backfill_day_options: Devices.backfill_day_options(),
      connection: live && connection(live)
    }
  end

  defp live(%{status: status} = connection) when status in ["active", "error"], do: connection
  defp live(_connection), do: nil

  defp connection(connection) do
    %{
      status: connection.status,
      connected_at: connection.connected_at,
      last_synced_at: connection.last_synced_at,
      sync_prefs: Map.merge(Devices.default_prefs(), connection.sync_prefs || %{}),
      backfill_days: connection.backfill_days,
      backfill_status: connection.backfill_status,
      backfill_progress: Devices.backfill_progress(connection),
      last_error: connection.last_error,
      needs_reconnect: connection.status == "error"
    }
  end

  @doc """
  A phone's health row (ADR-172): `native_only` until the store app
  connects it (the web says «Με την εφαρμογή»), then `connected` with what
  syncs, the last sync and where the app reads from next.
  """
  def phone_row(provider, connection) do
    live = if match?(%{status: "active"}, connection), do: connection

    %{
      provider: provider,
      status: if(live, do: "connected", else: "native_only"),
      sync_prefs: Map.merge(Devices.default_prefs(provider), (live && live.sync_prefs) || %{}),
      history_days: Devices.phone_history_days(),
      connection: live && phone_connection(provider, live)
    }
  end

  defp phone_connection(provider, connection) do
    %{
      status: connection.status,
      connected_at: connection.connected_at,
      last_synced_at: connection.last_synced_at,
      sync_prefs: Map.merge(Devices.default_prefs(provider), connection.sync_prefs || %{}),
      read_from: Devices.phone_read_from(connection)
    }
  end

  @doc "A watch workout of its own, as a journal entry."
  def activity(activity) do
    %{
      id: activity.id,
      organization_id: activity.organization_id,
      provider: activity.provider,
      state: activity.state,
      sport: activity.sport,
      activity_type: activity.activity_type,
      title: activity.title,
      started_at: activity.started_at,
      started_tz: activity.started_tz,
      duration_seconds: activity.duration_seconds,
      distance_meters: activity.distance_meters,
      avg_heart_rate: activity.avg_heart_rate,
      max_heart_rate: activity.max_heart_rate,
      calories: activity.calories,
      class_id: activity.class_id,
      journal_visibility: activity.journal_visibility,
      candidates: Enum.map(activity.candidates || [], &candidate/1)
    }
  end

  @doc "The watch's numbers on an entry they merged into («από Garmin»)."
  def metrics(activity) do
    %{
      id: activity.id,
      provider: activity.provider,
      sport: activity.sport,
      started_at: activity.started_at,
      duration_seconds: activity.duration_seconds,
      distance_meters: activity.distance_meters,
      avg_heart_rate: activity.avg_heart_rate,
      max_heart_rate: activity.max_heart_rate,
      calories: activity.calories
    }
  end

  defp candidate(candidate) do
    %{
      kind: candidate["kind"],
      id: candidate["id"],
      organization_id: candidate["organization_id"],
      title: candidate["title"],
      starts_at: candidate["starts_at"],
      ends_at: candidate["ends_at"]
    }
  end
end
