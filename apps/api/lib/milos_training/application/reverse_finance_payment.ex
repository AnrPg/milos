defmodule MilosTraining.Application.ReverseFinancePayment do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.{Finance, Identity}

  @doc """
  Records an audited payment reversal. Finance issues the refund receipt
  (ADR-108) in the same transaction; this service supplies the receipt's
  party names (organization and member) from their owning contexts so the
  immutable receipt snapshot is self-contained. Client-supplied
  `receipt_party` values are always overwritten.
  """
  def call(context, user_id, payment_id, admin_id, params) do
    case Finance.get_member_profile(user_id) do
      nil ->
        {:error, :not_found}

      profile ->
        params =
          params
          |> Map.put("created_by_id", admin_id)
          |> Map.put("receipt_party", receipt_party(context, user_id))

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

          {:ok,
           Map.put(
             reversal,
             :refund_receipt,
             Finance.get_refund_receipt_for_reversal(reversal.id)
           )}
        end
    end
  end

  def call(user_id, payment_id, admin_id, params),
    do: call(nil, user_id, payment_id, admin_id, params)

  defp receipt_party(context, user_id) do
    %{
      "organization_name" => organization_name(context),
      "member_display_name" => member_display_name(user_id)
    }
  end

  defp organization_name(%{organization: %{name: name}}) when is_binary(name), do: name
  defp organization_name(_context), do: nil

  defp member_display_name(user_id) do
    case Identity.find_by_id(user_id) do
      %{display_nickname: name} when is_binary(name) and name != "" -> name
      %{nickname: name} when is_binary(name) -> name
      _ -> nil
    end
  end
end
