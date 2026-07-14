defmodule MilosTraining.Application.RecordFinancePayment do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance

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

          {:ok, payment}
        end
    end
  end
end
