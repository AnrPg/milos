defmodule Palee.Application.CreateFinanceReceipt do
  alias Palee.Application.{GoLive, RecordAnalyticsEvent, RecordFinancePayment}
  alias Palee.Application.Fiscal.PaymentDocuments
  alias Palee.Finance

  @doc """
  ADR-184: the same, refused with `:business_not_activated` when a business
  in demo mode would take money from anyone but one of its mock people.
  """
  def call(context, user_id, admin_id, params) do
    with :ok <- GoLive.check_payment(context, user_id),
         {:ok, receipt} <- call(user_id, admin_id, params) do
      # ADR-262: the legal document of the money received.
      {:ok, PaymentDocuments.attach(context, receipt, admin_id)}
    end
  end

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
          payment_method: receipt.payment.payment_method,
          membership_package_subscription_id: receipt.membership_package_subscription_id
        }
      })

      RecordFinancePayment.announce_payment(membership, receipt.payment)
      {:ok, receipt}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
