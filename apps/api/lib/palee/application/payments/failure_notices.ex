defmodule Palee.Application.Payments.FailureNotices do
  @moduledoc """
  `Payments.Ports.Notifier` over Notifications (ADR-260). The member hears
  about every declined charge, with a link to pay with another card; staff
  who manage billing hear when the last retry failed. Each follows the
  business's `notify_member` / `notify_staff` options. Deduplicated per
  charge attempt, so a retried job never notifies twice.
  """

  @behaviour Palee.Payments.Ports.Notifier

  require Logger

  alias Palee.{Notifications, Organizations}
  alias Palee.Payments.Domain.AccountOptions

  @impl true
  def charge_declined(context, intent, %{final: final, options: options}) do
    payload = %{
      organization_id: context.organization_id,
      payment_id: intent.id,
      amount_cents: intent.amount_cents,
      currency: intent.currency,
      description: intent.description,
      final: final
    }

    if AccountOptions.notify_member?(options) and is_binary(intent.user_id) do
      deliver("payment_failed", intent.user_id, payload, %{
        url: "/me/payments?payment=#{intent.id}",
        dedupe_key: "payment_failed:#{intent.id}:#{intent.attempts}"
      })
    end

    if final and AccountOptions.notify_staff?(options) do
      context.organization_id
      |> Organizations.list_user_ids_with_capability(:manage_billing)
      |> Enum.each(fn user_id ->
        deliver("payment_needs_attention", user_id, payload, %{
          url: "/admin/finance?tab=queues",
          dedupe_key: "payment_needs_attention:#{intent.id}:#{user_id}"
        })
      end)
    end

    :ok
  end

  @impl true
  def card_link(context, intent, %DateTime{} = now) do
    deliver(
      "payment_failed",
      intent.user_id,
      %{
        organization_id: context.organization_id,
        payment_id: intent.id,
        amount_cents: intent.amount_cents,
        currency: intent.currency,
        description: intent.description,
        final: intent.status == "failed"
      },
      %{
        url: "/me/payments?payment=#{intent.id}",
        # At most one reminder a minute, so a double press sends one.
        dedupe_key: "payment_card_link:#{intent.id}:#{div(DateTime.to_unix(now), 60)}"
      }
    )

    :ok
  end

  defp deliver(type, user_id, payload, extra) do
    Notifications.process_event(type, payload |> Map.merge(extra) |> Map.put(:user_id, user_id))
  rescue
    error ->
      Logger.warning("payment_notice_failed type=#{type} reason=#{Exception.message(error)}")
      :ok
  end
end
