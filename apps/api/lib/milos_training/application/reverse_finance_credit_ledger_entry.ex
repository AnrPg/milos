defmodule MilosTraining.Application.ReverseFinanceCreditLedgerEntry do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance

  def call(user_id, entry_id, admin_id, params) do
    case Finance.get_member_profile(user_id) do
      nil ->
        {:error, :not_found}

      profile ->
        params = Map.put(params, "created_by_id", admin_id)

        with {:ok, reversal} <-
               Finance.reverse_credit_ledger_entry(profile.membership.id, entry_id, params) do
          RecordAnalyticsEvent.call_unsafe("finance_credit_reversed", %{
            user_id: user_id,
            context_type: "finance_credit_ledger_entry",
            context_id: reversal.id,
            metadata: %{
              membership_id: profile.membership.id,
              reversed_credit_ledger_entry_id: entry_id,
              finance_invoice_id: reversal.finance_invoice_id,
              membership_payment_id: reversal.membership_payment_id,
              amount_cents: reversal.amount_cents
            }
          })

          {:ok, reversal}
        end
    end
  end
end
