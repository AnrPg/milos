defmodule Palee.Application.Documents.HealthCertificateReminders do
  @moduledoc """
  Tells clients their health certificate expires soon (ADR-252): once per
  certificate and expiry date, when the box requires certificates and the
  expiry falls within its reminder window (30 days by default). The
  certificate is marked before the client is told, and the notification's
  dedupe key keeps a retried job from telling them twice.
  """

  require Logger

  alias Palee.Application.Documents.DocumentsAdmin
  alias Palee.{Documents, Notifications, Organizations}

  @doc "Reminds every due holder of one box; returns how many were told."
  def remind(context, now \\ DateTime.utc_now()) do
    today = Organizations.local_date(context, now)

    context
    |> Documents.health_reminders_due(today)
    |> Enum.filter(&Organizations.client_role(context, &1.user_id))
    |> Enum.reduce(0, fn certificate, count ->
      :ok = Documents.mark_health_reminded(context, certificate)

      Notifications.dispatch_event(:health_certificate_expiring, %{
        user_id: certificate.user_id,
        organization_id: context.organization_id,
        expires_on: Date.to_iso8601(certificate.expires_on),
        business_name: DocumentsAdmin.business_name(context),
        dedupe_key: "health_certificate_expiring:#{certificate.id}:#{certificate.expires_on}"
      })

      count + 1
    end)
  end

  @doc "Runs `remind/2` for every active box."
  def remind_all(now \\ DateTime.utc_now()) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      try do
        remind(%{organization_id: organization.id, organization: organization}, now)
      rescue
        error ->
          Logger.error(
            "health certificate reminders failed for #{organization.id}: #{Exception.message(error)}"
          )
      end
    end)
  end
end
