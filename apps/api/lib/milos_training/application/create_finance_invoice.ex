defmodule MilosTraining.Application.CreateFinanceInvoice do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance

  def call(user_id, admin_id, params) do
    with {:ok, membership_id} <- membership_id_for_user(user_id),
         {:ok, invoice} <- Finance.create_invoice(membership_id, params) do
      record_event("finance_invoice_created", user_id, admin_id, invoice)
      {:ok, invoice}
    end
  end

  defp membership_id_for_user(user_id) do
    case Finance.get_member_profile(user_id) do
      nil -> {:error, :not_found}
      profile -> {:ok, profile.membership.id}
    end
  end

  defp record_event(event_name, user_id, admin_id, invoice) do
    RecordAnalyticsEvent.call_unsafe(event_name, %{
      user_id: user_id,
      context_type: "finance_invoice",
      context_id: invoice.id,
      metadata: %{
        admin_id: admin_id,
        invoice_type: invoice.invoice_type,
        status: invoice.status,
        total_cents: invoice.total_cents,
        balance_due_cents: invoice.balance_due_cents
      }
    })
  end
end
