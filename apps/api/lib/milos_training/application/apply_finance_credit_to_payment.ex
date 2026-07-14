defmodule MilosTraining.Application.ApplyFinanceCreditToPayment do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance

  def call(user_id, payment_id, admin_id, params) do
    case Finance.get_member_profile(user_id) do
      nil ->
        {:error, :not_found}

      profile ->
        params = Map.put(params, "created_by_id", admin_id)

        with {:ok, entry} <-
               Finance.apply_credit_to_payment(profile.membership.id, payment_id, params) do
          RecordAnalyticsEvent.call_unsafe("finance_credit_applied_to_payment", %{
            user_id: user_id,
            context_type: "finance_credit_ledger_entry",
            context_id: entry.id,
            metadata: %{
              membership_id: profile.membership.id,
              membership_payment_id: payment_id,
              amount_cents: entry.amount_cents,
              source_type: entry.source_type,
              entry_type: entry.entry_type
            }
          })

          {:ok, entry}
        end
    end
  end
end
