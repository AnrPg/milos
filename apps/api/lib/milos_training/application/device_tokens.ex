defmodule MilosTraining.Application.DeviceTokens do
  @moduledoc """
  A connection's access token, refreshed before it runs out (ADR-161), and
  the bookkeeping of failures: each one is counted; at the third in a row
  the connection turns `error` and the person hears once
  (`device_sync_error`) that sync stopped and «Επανασύνδεση» will fix it. A
  success clears the count.
  """

  require Logger

  alias MilosTraining.{Devices, Notifications}

  @doc "Connection columns from a token response."
  def token_attrs(tokens, now) do
    %{
      access_token: tokens.access_token,
      token_expires_at: expires(tokens.expires_in, now),
      refresh_token_expires_at: expires(tokens[:refresh_token_expires_in], now)
    }
    |> then(fn attrs ->
      if is_binary(tokens[:refresh_token]),
        do: Map.put(attrs, :refresh_token, tokens.refresh_token),
        else: attrs
    end)
  end

  @doc "`{:ok, token, connection}` with a token good for the next half hour."
  def access_token(context, connection, now) do
    cond do
      not is_binary(connection.access_token) ->
        {:error, :device_not_connected}

      Devices.refresh_due?(connection.token_expires_at, now) ->
        refresh(context, connection, now)

      true ->
        {:ok, connection.access_token, connection}
    end
  end

  @doc "Refreshes now (the token sweep)."
  def refresh(context, connection, now) do
    case connection.refresh_token &&
           Devices.garmin().refresh(connection.refresh_token) do
      {:ok, tokens} ->
        {:ok, updated} =
          Devices.with_context(context, fn ->
            Devices.update_connection(connection, token_attrs(tokens, now))
          end)

        {:ok, updated.access_token, updated}

      nil ->
        record_failure(context, connection, "no refresh token")
        {:error, :device_not_connected}

      {:error, :garmin_invalid_grant} ->
        # Garmin no longer honours the grant: only a new sign-in helps.
        record_failure(context, connection, "garmin_invalid_grant", force: true)
        {:error, :device_reconnect_required}

      {:error, reason} ->
        record_failure(context, connection, inspect(reason))
        {:error, :garmin_unavailable}
    end
  end

  @doc "Counts one failure; turns the connection to `error` and notifies once."
  def record_failure(context, connection, message, opts \\ []) do
    connection =
      if Keyword.get(opts, :force, false),
        do: %{connection | consecutive_failures: max(connection.consecutive_failures, 2)},
        else: connection

    {changes, notify?} = Devices.failure_changes(connection, message)

    changes =
      if notify?, do: Map.put(changes, :error_notified_at, DateTime.utc_now()), else: changes

    result =
      Devices.with_context(context, fn ->
        case Devices.get_connection(connection.user_id, connection.provider) do
          nil -> {:error, :not_found}
          current -> Devices.update_connection(current, changes)
        end
      end)

    if notify?, do: notify(connection)
    result
  end

  @doc "A successful sync."
  def record_success(context, connection, now) do
    Devices.with_context(context, fn ->
      Devices.update_connection(connection, Devices.success_changes(connection, now))
    end)
  end

  defp notify(connection) do
    Notifications.dispatch_event(:device_sync_error, %{
      user_id: connection.user_id,
      provider: connection.provider,
      dedupe_key: "device_sync_error:#{connection.id}:#{Date.utc_today()}"
    })
  rescue
    error -> Logger.error("device sync error notice failed #{Exception.message(error)}")
  end

  defp expires(seconds, now) when is_integer(seconds) and seconds > 0,
    do: DateTime.add(now, seconds, :second)

  defp expires(_seconds, _now), do: nil
end
