defmodule Palee.Workers.PackageExpiryReminderJob do
  @moduledoc """
  Notifies members whose package ends in exactly the package's reminder days
  (ADR-097). Runs daily, per active organization; the exact-day match makes
  each subscription produce one reminder.
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3, unique: [period: 3_600]

  alias Palee.{Finance, Notifications, Organizations}

  @impl Oban.Worker
  def perform(_job) do
    # ADR-179: each gym's own "today" (the run is daily, so each gym's day
    # still advances by exactly one per run).
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      %{organization_id: organization.id}
      |> Finance.subscriptions_due_for_expiry_reminder(Organizations.local_today(organization.id))
      |> Enum.each(&Notifications.process_event("package_expiring", &1))
    end)

    :ok
  end
end
