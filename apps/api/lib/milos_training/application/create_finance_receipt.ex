defmodule MilosTraining.Application.CreateFinanceReceipt do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance

  def call(user_id, admin_id, params) do
    with %{membership: membership} <- Finance.get_member_profile(user_id),
         receipt_params <-
           params
           |> Map.put_new(:created_by_id, admin_id)
           |> Map.put_new("created_by_id", admin_id),
         {:ok, receipt} <- Finance.create_receipt(membership.id, receipt_params) do
      RecordAnalyticsEvent.call_unsafe("finance_receipt_issued", %{
        user_id: user_id,
        context_type: "finance_invoice",
        context_id: receipt.invoice.id,
        metadata: %{
          admin_id: admin_id,
          reference: receipt.reference,
          amount_cents: receipt.amount_cents,
          payment_method: receipt.payment.payment_method
        }
      })

      {:ok, receipt}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
