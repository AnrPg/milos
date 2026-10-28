defmodule Palee.Infrastructure.Observability.EmailProbe do
  @moduledoc """
  Gauges of the email outbox for the budget alarm (ADR-212): today's sent
  mail against `EMAIL_DAILY_BUDGET` and `EMAIL_DAILY_HARD_CAP`, the
  messages waiting for the next day (`deferred`), and the SMTP key's days
  left when `SMTP_KEY_EXPIRES_ON` is set.

  Emits `[:palee, :email, :budget]` (`sent_today`, `daily_budget`,
  `hard_cap`, `deferred`) and `[:palee, :email, :smtp_key]` (`days_left`).
  """

  require Logger

  @doc "Emits the gauges. Never raises (poller-safe)."
  def measure(now \\ DateTime.utc_now()) do
    :telemetry.execute([:palee, :email, :budget], Palee.Email.sending_stats(now), %{})

    case Palee.Email.smtp_key_status(DateTime.to_date(now)) do
      %{days_left: days} when is_integer(days) ->
        :telemetry.execute([:palee, :email, :smtp_key], %{days_left: days}, %{})

      _unknown ->
        :ok
    end
  rescue
    error ->
      Logger.warning("email_probe_failed #{Exception.message(error)}")
      :ok
  end
end
