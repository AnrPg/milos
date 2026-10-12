defmodule MilosTraining.Workers.PackageExpiryReminderJob do
  @moduledoc """
  Notifies members whose package ends in exactly the package's reminder days
  (ADR-097). Runs daily, per active organization; the exact-day match makes
  each subscription produce one reminder.
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3, unique: [period: 3_600]

  alias MilosTraining.{Finance, Notifications}
  alias MilosTraining.Organizations.OrganizationStore

  @impl Oban.Worker
  def perform(_job) do
    today = Date.utc_today()

    OrganizationStore.list_organizations()
    |> Enum.filter(fn %{organization: organization} -> organization.status == :active end)
    |> Enum.each(fn %{organization: organization} ->
      %{organization_id: organization.id}
      |> Finance.subscriptions_due_for_expiry_reminder(today)
      |> Enum.each(&Notifications.process_event("package_expiring", &1))
    end)

    :ok
  end
end
