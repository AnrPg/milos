defmodule MilosTraining.Workers.PaymentReminderJob do
  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias MilosTraining.{Finance, Notifications}

  @impl Oban.Worker
  def perform(_job) do
    settings = Finance.get_finance_settings()
    interval_days = Map.get(settings, :payment_reminder_interval_days, 7)

    memberships = Finance.memberships_needing_payment_reminder(interval_days)

    Enum.each(memberships, fn %{
                                membership_id: membership_id,
                                user_id: user_id,
                                outstanding_balance_cents: cents
                              } ->
      Notifications.process_event("payment_reminder", %{
        user_id: user_id,
        outstanding_balance_cents: cents
      })

      Finance.update_membership_reminder_timestamp(membership_id)
    end)

    :ok
  end
end
