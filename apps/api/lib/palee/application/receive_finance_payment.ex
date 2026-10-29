defmodule Palee.Application.ReceiveFinancePayment do
  @moduledoc """
  ADR-222: staff record money a client handed over (cash, card on the box's
  own terminal, bank transfer) and get the document the box's billing setup
  calls for: the open invoice it settles, a receipt or a paid invoice.
  """

  alias Palee.Application.{GoLive, RecordAnalyticsEvent, RecordFinancePayment}
  alias Palee.Finance

  @doc """
  ADR-184: refused with `:business_not_activated` when a business in demo
  mode would take money from anyone but one of its mock people.
  """
  def call(context, user_id, admin_id, params) do
    with :ok <- GoLive.check_payment(context, user_id), do: call(user_id, admin_id, params)
  end

  def call(user_id, admin_id, params) do
    params =
      params
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.put("created_by_id", admin_id)

    with %{membership: membership} <- Finance.get_member_profile(user_id),
         {:ok, received} <- Finance.receive_payment(membership.id, params) do
      # A retried request returns the first answer and tells nobody again.
      unless received.replayed, do: announce(membership, user_id, admin_id, received)
      {:ok, received}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp announce(membership, user_id, admin_id, received) do
    RecordAnalyticsEvent.call_unsafe("payment_recorded", %{
      user_id: user_id,
      context_type: "membership_payment",
      context_id: received.payment.id,
      metadata: %{
        admin_id: admin_id,
        membership_id: membership.id,
        document_type: received.document_type,
        reference: received.reference,
        finance_invoice_id: received.invoice.id,
        amount_cents: received.amount_cents,
        payment_method: received.payment.payment_method
      }
    })

    RecordFinancePayment.announce_payment(membership, received.payment)
  end
end
