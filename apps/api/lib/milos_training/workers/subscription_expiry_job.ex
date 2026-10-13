defmodule MilosTraining.Workers.SubscriptionExpiryJob do
  @moduledoc """
  Daily: tells clients about their subscription ending, and keeps entitlement
  snapshots in step with the calendar.

    * `subscription_expiring` – sent once, `subscription_expiry_reminder_days`
      before a subscription that has not been renewed ends;
    * `subscription_grace` – sent once after it ended, while the member is in
      the `subscription_grace_days` slack (they keep access until it is over,
      then lose it, e.g. they can no longer book classes);
    * `access_ended` – when the slack is over (or a payment stays overdue past
      it) the client loses every entitlement: new bookings, starting workouts,
      assignments and coaching touchpoints are refused by `EntitlementPolicy`,
      and their upcoming class bookings are cancelled here (the places and
      class allowances are released).

  Notifications go to the client (in-app and push, in their language).
  """
  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias MilosTraining.{Finance, Notifications, Scheduling}
  alias MilosTraining.Finance.Domain.InvoiceLifecycle
  alias MilosTraining.Organizations.OrganizationStore

  @impl Oban.Worker
  def perform(_job) do
    OrganizationStore.list_organizations()
    |> Enum.filter(fn %{organization: organization} -> organization.status == :active end)
    |> Enum.each(fn %{organization: organization} -> run(%{organization_id: organization.id}) end)

    :ok
  end

  @doc "Runs the job for one organization (`context` carries its id)."
  def run(context, today \\ Date.utc_today()) do
    settings = Finance.get_finance_settings(context)
    reminder_days = Map.get(settings, :subscription_expiry_reminder_days, 5) || 0
    grace_days = Map.get(settings, :subscription_grace_days, 3) || 0

    context
    |> Finance.subscriptions_needing_expiry_notice(:expiry_reminder, reminder_days)
    |> Enum.each(fn subscription ->
      notify(context, subscription, "subscription_expiring", :expiry_reminder, %{
        days_left: Date.diff(subscription.ends_on, today),
        grace_days: grace_days
      })
    end)

    context
    |> Finance.subscriptions_needing_expiry_notice(:grace_notice, grace_days)
    |> Enum.each(fn subscription ->
      notify(context, subscription, "subscription_grace", :grace_notice, %{
        grace_until:
          Date.to_iso8601(InvoiceLifecycle.grace_until(subscription.ends_on, grace_days))
      })
    end)

    context
    |> Finance.refresh_entitlement_snapshots()
    |> Enum.each(&revoke_access(context, &1))

    :ok
  end

  defp revoke_access(context, %{user_id: user_id} = lost) do
    cancelled =
      case Scheduling.cancel_active_future_bookings_for_user(context, user_id) do
        {:ok, release_facts} ->
          Enum.each(release_facts, &release_class_visit(context, &1))
          length(release_facts)

        _error ->
          0
      end

    Notifications.process_event("access_ended", %{
      user_id: user_id,
      membership_id: lost.membership_id,
      reason: if(lost.status == "blocked", do: "overdue_payment", else: "subscription_ended"),
      cancelled_bookings: cancelled
    })
  end

  defp release_class_visit(context, fact) do
    Finance.release_entitlement_source(
      context,
      fact.user_id,
      "scheduling",
      fact.scheduled_class_id,
      :class_visits,
      %{
        reason: "Access ended",
        idempotency_key: "access-ended-booking-release:#{fact.booking_id}"
      }
    )
  end

  defp notify(context, subscription, event, kind, extra) do
    payload =
      Map.merge(extra, %{
        user_id: subscription.user_id,
        subscription_id: subscription.subscription_id,
        package_name: subscription.package_name,
        ends_on: Date.to_iso8601(subscription.ends_on)
      })

    case Notifications.process_event(event, payload) do
      :ok -> Finance.mark_subscription_notice_sent(context, subscription.subscription_id, kind)
      _failed -> :ok
    end
  end
end
