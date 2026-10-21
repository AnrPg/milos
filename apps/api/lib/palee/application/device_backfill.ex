defmodule Palee.Application.DeviceBackfill do
  @moduledoc """
  The history import chosen at connect (ADR-161, board 16 Q5): 30 or 90 days
  cut into 10-day windows, asked from Garmin one window at a time for the
  kinds the person wants. Garmin then pushes those summaries like new ones,
  so the same dedupe and merge rules apply. Progress («Εισαγωγή… 40%») is
  the share of windows asked.
  """

  require Logger

  alias Palee.Application.DeviceTokens
  alias Palee.Devices

  @provider "garmin"
  @pause_seconds 20

  @doc "Asks for the next window; `{:more, connection}`, `:done` or `{:error, reason}`."
  def run_next(connection_id, user_id, now \\ DateTime.utc_now()) do
    context = %{user_id: user_id}

    case Devices.with_context(context, fn -> Devices.get_connection(user_id, @provider) end) do
      %{id: ^connection_id, status: "active", backfill_status: "running"} = connection ->
        windows = Devices.backfill_windows(connection.backfill_days, anchor(connection, now))
        step(context, connection, Enum.at(windows, connection.backfill_windows_done), now)

      _other ->
        :done
    end
  end

  # Windows are measured from the moment of connecting, so a retry asks the
  # same ones.
  defp anchor(connection, now), do: connection.connected_at || now

  defp step(context, connection, nil, _now) do
    {:ok, _done} = update(context, connection, %{backfill_status: "done"})
    :done
  end

  defp step(context, connection, {from, to}, now) do
    types =
      ~w(activity sleep weight daily)
      |> Enum.filter(&Devices.wanted?(connection.sync_prefs || %{}, &1))
      |> Devices.garmin_backfill_types()

    with {:ok, token, connection} <- DeviceTokens.access_token(context, connection, now),
         :ok <- request_all(token, types, from, to) do
      done = connection.backfill_windows_done + 1
      finished? = done >= connection.backfill_windows_total

      {:ok, updated} =
        update(context, connection, %{
          backfill_windows_done: min(done, connection.backfill_windows_total),
          backfill_status: if(finished?, do: "done", else: "running")
        })

      if finished?, do: :done, else: {:more, updated}
    else
      {:error, reason} ->
        Logger.warning("garmin backfill window failed #{inspect(reason)}")
        DeviceTokens.record_failure(context, connection, inspect(reason))
        {:error, reason}
    end
  end

  defp request_all(token, types, from, to) do
    Enum.reduce_while(types, :ok, fn type, :ok ->
      case Devices.garmin().request_backfill(token, type, from, to) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc "The job: one window, then the next one a little later."
  def perform(connection_id, user_id) do
    case run_next(connection_id, user_id) do
      {:more, _connection} ->
        Devices.sync_queue().enqueue_backfill(connection_id, user_id, schedule_in: @pause_seconds)

      :done ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Every window at once (background jobs off)."
  def run_all(connection_id, user_id, now \\ DateTime.utc_now(), budget \\ 20)

  def run_all(_connection_id, _user_id, _now, 0), do: :ok

  def run_all(connection_id, user_id, now, budget) do
    case run_next(connection_id, user_id, now) do
      {:more, _connection} -> run_all(connection_id, user_id, now, budget - 1)
      :done -> :ok
      error -> error
    end
  end

  defp update(context, connection, attrs),
    do: Devices.with_context(context, fn -> Devices.update_connection(connection, attrs) end)
end
