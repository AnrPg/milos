defmodule Palee.Application.RecordFinancePayment do
  alias Palee.Application.{GoLive, RecordAnalyticsEvent}
  alias Palee.Finance

  @doc false
  # ADR-156: a package payment is a fact other contexts follow (the invite
  # funnel's «paid»). Event payments go through Finance receipts of their own
  # and never come here.
  def announce_payment(membership, payment) do
    if payment.payment_status == "paid" and (payment.amount_cents || 0) > 0 do
      Palee.DomainEvents.publish(:membership_payment_recorded, %{
        organization_id: membership.organization_id,
        user_id: membership.user_id,
        membership_id: membership.id,
        payment_id: payment.id,
        amount_cents: payment.amount_cents,
        at: DateTime.utc_now()
      })
    end

    :ok
  end

  @doc """
  ADR-184: the same, refused with `:business_not_activated` when a business
  in demo mode would take money from anyone but one of its mock people.
  """
  def call(context, user_id, params) do
    with :ok <- GoLive.check_payment(context, user_id), do: call(user_id, params)
  end

  def call(user_id, params) do
    case Finance.get_member_profile(user_id) do
      nil ->
        {:error, :not_found}

      profile ->
        with {:ok, payment} <- Finance.record_payment(profile.membership.id, params) do
          RecordAnalyticsEvent.call_unsafe("payment_recorded", %{
            user_id: user_id,
            context_type: "membership_payment",
            context_id: payment.id,
            metadata: %{
              membership_id: profile.membership.id,
              amount_cents: payment.amount_cents,
              payment_method: payment.payment_method,
              payment_status: payment.payment_status
            }
          })

          announce_payment(profile.membership, payment)
          {:ok, payment}
        end
    end
  end
end
