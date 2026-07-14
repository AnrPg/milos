defmodule MilosTraining.Application.VoidFinanceInvoice do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance

  def call(invoice_id, admin_id, params) do
    with {:ok, invoice} <- Finance.void_invoice(invoice_id, params) do
      RecordAnalyticsEvent.call_unsafe("finance_invoice_voided", %{
        user_id: invoice.user_id,
        context_type: "finance_invoice",
        context_id: invoice.id,
        metadata: %{admin_id: admin_id, status: invoice.status}
      })

      {:ok, invoice}
    end
  end
end
