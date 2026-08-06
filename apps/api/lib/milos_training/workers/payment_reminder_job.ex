defmodule MilosTraining.Workers.PaymentReminderJob do
  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias MilosTraining.{Finance, Notifications}
  alias MilosTraining.Organizations.OrganizationStore

  @impl Oban.Worker
  def perform(_job) do
    OrganizationStore.list_organizations()
    |> Enum.filter(fn %{organization: organization} -> organization.status == :active end)
    |> Enum.each(fn %{organization: organization} -> remind_for_organization(organization) end)

    :ok
  end

  defp remind_for_organization(organization) do
    context = %{organization_id: organization.id}
    settings = Finance.get_finance_settings(context)
    interval_days = Map.get(settings, :payment_reminder_interval_days, 7)

    memberships = Finance.memberships_needing_payment_reminder(context, interval_days)

    Enum.each(memberships, fn %{
                                membership_id: membership_id,
                                user_id: user_id,
                                outstanding_balance_cents: cents
                              } ->
      Notifications.process_event("payment_reminder", %{
        user_id: user_id,
        outstanding_balance_cents: cents
      })

      Finance.update_membership_reminder_timestamp(context, membership_id)
    end)
  end
end
