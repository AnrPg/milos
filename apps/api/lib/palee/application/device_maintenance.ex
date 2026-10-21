defmodule Palee.Application.DeviceMaintenance do
  @moduledoc """
  The device health sweep (ADR-161): refreshes access tokens that end within
  half an hour. A failed refresh counts as a failure of the connection; the
  third in a row turns it `error` and tells the person once
  (`DeviceTokens.record_failure/4`). A definer lookup names whose tokens are
  due; each connection is then handled in its owner's session.
  """

  require Logger

  alias Palee.Application.DeviceTokens
  alias Palee.Devices

  @batch 100
  @provider "garmin"

  def call(now \\ DateTime.utc_now()) do
    now
    |> Devices.refresh_horizon()
    |> Devices.connections_due_refresh(@batch)
    |> Enum.map(fn {connection_id, user_id} -> refresh(connection_id, user_id, now) end)
    |> Enum.frequencies()
  end

  @doc "One connection's refresh (public for tests)."
  def refresh(connection_id, user_id, now) do
    context = %{user_id: user_id}

    case Devices.with_context(context, fn -> Devices.get_connection(user_id, @provider) end) do
      %{id: ^connection_id} = connection ->
        case DeviceTokens.refresh(context, connection, now) do
          {:ok, _token, _connection} -> :refreshed
          {:error, _reason} -> :failed
        end

      _gone ->
        :skipped
    end
  rescue
    error ->
      Logger.error("device token refresh #{connection_id} failed: #{Exception.message(error)}")
      :failed
  end
end
