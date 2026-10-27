defmodule Palee.Application.SmtpKeyExpiryCheck do
  @moduledoc """
  The daily check of the SMTP key's expiry (ADR-212, `SMTP_KEY_EXPIRES_ON`).
  Brevo's SMTP keys expire after a year; after that every email fails.

  It always reports the days left (`[:palee, :email, :smtp_key]`, the
  `palee_email_smtp_key_days_left` gauge the alert rules read). From 30
  days before, it logs a warning and tells every vendor in the bell
  (`email_key_expiring`) on the 30th, 14th and 7th day before and on each
  of the last 3 days; once expired, it logs an error and tells them every
  day. One notification per vendor per day at most (dedupe key).
  """

  require Logger

  alias Palee.{Email, Notifications, Organizations}

  @notify_on [30, 14, 7, 3, 2, 1, 0]

  @spec call(Date.t()) :: {:ok, :unknown | :ok | :notified | :quiet}
  def call(today \\ Date.utc_today()) do
    status = Email.smtp_key_status(today)

    if is_integer(status.days_left) do
      :telemetry.execute([:palee, :email, :smtp_key], %{days_left: status.days_left}, %{})
    end

    case status.state do
      :unknown ->
        {:ok, :unknown}

      :ok ->
        {:ok, :ok}

      {:expiring, days} ->
        Logger.warning("smtp_key_expiring days_left=#{days} expires_on=#{status.expires_on}")
        if days in @notify_on, do: notify(status, today), else: {:ok, :quiet}

      :expired ->
        Logger.error("smtp_key_expired expires_on=#{status.expires_on}")
        notify(status, today)
    end
  end

  defp notify(status, today) do
    payload = %{
      expires_on: Date.to_iso8601(status.expires_on),
      days_left: status.days_left,
      dedupe_key: "email_key_expiring:#{status.expires_on}:#{today}"
    }

    Organizations.list_active_vendor_user_ids()
    |> Enum.each(fn user_id ->
      Notifications.dispatch_event(:email_key_expiring, Map.put(payload, :user_id, user_id))
    end)

    {:ok, :notified}
  end
end
