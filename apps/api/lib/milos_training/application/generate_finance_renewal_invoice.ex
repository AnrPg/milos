defmodule MilosTraining.Application.GenerateFinanceRenewalInvoice do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance

  def call(user_id, admin_id, params) do
    with {:ok, membership_id} <- membership_id_for_user(user_id),
         {:ok, invoice} <- Finance.generate_renewal_invoice(membership_id, params) do
      RecordAnalyticsEvent.call_unsafe("finance_renewal_invoice_generated", %{
        user_id: user_id,
        context_type: "finance_invoice",
        context_id: invoice.id,
        metadata: %{
          admin_id: admin_id,
          membership_id: membership_id,
          total_cents: invoice.total_cents,
          service_period_start: invoice.service_period_start,
          service_period_end: invoice.service_period_end
        }
      })

      {:ok, invoice}
    end
  end

  defp membership_id_for_user(user_id) do
    case Finance.get_member_profile(user_id) do
      nil -> {:error, :not_found}
      profile -> {:ok, profile.membership.id}
    end
  end
end
