defmodule MilosTraining.Application.ReverseFinancePayment do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance

  def call(user_id, payment_id, admin_id, params) do
    case Finance.get_member_profile(user_id) do
      nil ->
        {:error, :not_found}

      profile ->
        params = Map.put(params, "created_by_id", admin_id)

        with {:ok, reversal} <- Finance.reverse_payment(profile.membership.id, payment_id, params) do
          RecordAnalyticsEvent.call_unsafe("finance_payment_reversed", %{
            user_id: user_id,
            context_type: "finance_payment_reversal",
            context_id: reversal.id,
            metadata: %{
              membership_id: profile.membership.id,
              membership_payment_id: payment_id,
              finance_invoice_id: reversal.finance_invoice_id,
              amount_cents: reversal.amount_cents
            }
          })

          {:ok, reversal}
        end
    end
  end
end
