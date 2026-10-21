defmodule MilosTraining.Devices.Domain.ConnectionPolicy do
  @moduledoc """
  The life of a device connection (ADR-161, board 16 Q5–Q6): how long a
  sign-in may take, when a token needs refreshing, how often «Συγχρονισμός
  τώρα» may run, when repeated failures turn a connection to `error` (one
  notification, «Επανασύνδεση» on the row), and how the history import is
  cut into windows so its progress can be shown.
  """

  @sign_in_seconds 15 * 60
  @refresh_margin_seconds 30 * 60
  @sync_interval_seconds 5 * 60
  @failure_threshold 3
  @backfill_window_days 10

  def sign_in_seconds, do: @sign_in_seconds
  def failure_threshold, do: @failure_threshold
  def sync_interval_seconds, do: @sync_interval_seconds

  @doc "A pending sign-in older than this is refused at the return."
  def sign_in_expired?(nil, _now), do: true

  def sign_in_expired?(%DateTime{} = started_at, %DateTime{} = now),
    do: DateTime.diff(now, started_at, :second) > @sign_in_seconds

  @doc "Whether the access token should be refreshed before use."
  def refresh_due?(nil, _now), do: true

  def refresh_due?(%DateTime{} = expires_at, %DateTime{} = now),
    do: DateTime.diff(expires_at, now, :second) < @refresh_margin_seconds

  @doc "The sweep refreshes tokens ending before this instant."
  def refresh_horizon(%DateTime{} = now), do: DateTime.add(now, @refresh_margin_seconds, :second)

  @doc "«Συγχρονισμός τώρα» at most every five minutes."
  def validate_sync_request(nil, _now), do: :ok

  def validate_sync_request(%DateTime{} = last, %DateTime{} = now) do
    if DateTime.diff(now, last, :second) >= @sync_interval_seconds,
      do: :ok,
      else: {:error, :sync_too_soon}
  end

  @doc """
  The changes one more failure makes: the count, the message, and `error`
  once the threshold is reached. `notify?` is true exactly once per spell of
  failures (cleared by the next success).
  """
  def failure(%{consecutive_failures: count, status: status} = connection, message) do
    count = (count || 0) + 1
    failing? = count >= @failure_threshold and status in ["active", "error"]

    changes =
      %{consecutive_failures: count, last_error: truncate(message)}
      |> then(&if(failing?, do: Map.put(&1, :status, "error"), else: &1))

    {changes, failing? and is_nil(Map.get(connection, :error_notified_at))}
  end

  @doc "The changes a success makes: back to active, failures forgotten."
  def success(%{status: status}, %DateTime{} = now) do
    %{consecutive_failures: 0, last_error: nil, error_notified_at: nil, last_synced_at: now}
    |> then(&if(status == "error", do: Map.put(&1, :status, "active"), else: &1))
  end

  @doc "History windows `{from, to}`, oldest first, covering `days` before `now`."
  def backfill_windows(0, _now), do: []

  def backfill_windows(days, %DateTime{} = now) when is_integer(days) and days > 0 do
    start = DateTime.add(now, -days * 86_400, :second)
    step = @backfill_window_days * 86_400

    start
    |> Stream.iterate(&DateTime.add(&1, step, :second))
    |> Enum.take_while(&(DateTime.compare(&1, now) == :lt))
    |> Enum.map(fn from ->
      to = DateTime.add(from, step, :second)
      {from, if(DateTime.compare(to, now) == :gt, do: now, else: to)}
    end)
  end

  @doc "Progress of the history import, 0–100 (nil when there is none)."
  def backfill_progress(%{backfill_status: "none"}), do: nil
  def backfill_progress(%{backfill_status: "done"}), do: 100
  def backfill_progress(%{backfill_windows_total: 0}), do: 0

  def backfill_progress(%{backfill_windows_total: total, backfill_windows_done: done}),
    do: div(done * 100, total)

  @doc "The status the devices row shows."
  def row_status(nil, false), do: "unavailable"
  def row_status(nil, true), do: "disconnected"
  def row_status(%{status: "revoked"}, configured?), do: row_status(nil, configured?)
  def row_status(%{status: "active"}, _configured?), do: "connected"
  def row_status(%{status: status}, _configured?), do: status

  defp truncate(nil), do: nil
  defp truncate(message), do: message |> to_string() |> String.slice(0, 250)
end
