defmodule MilosTraining.Application.IssueFinanceInvoice do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance
  alias MilosTraining.Notifications

  def call(invoice_id, admin_id, params) do
    with {:ok, invoice} <- Finance.issue_invoice(invoice_id, params) do
      RecordAnalyticsEvent.call_unsafe("finance_invoice_issued", %{
        user_id: invoice.user_id,
        context_type: "finance_invoice",
        context_id: invoice.id,
        metadata: %{
          admin_id: admin_id,
          status: invoice.status,
          total_cents: invoice.total_cents,
          balance_due_cents: invoice.balance_due_cents
        }
      })

      Notifications.dispatch_event(:invoice_issued, invoice)

      {:ok, invoice}
    end
  end
end
