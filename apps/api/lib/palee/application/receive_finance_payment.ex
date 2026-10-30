defmodule Palee.Application.ReceiveFinancePayment do
  @moduledoc """
  ADR-222: staff record money a client handed over (cash, card on the box's
  own terminal, bank transfer) and get the document the box's billing setup
  calls for: the open invoice it settles, a receipt or a paid invoice.
  """

  alias Palee.Application.{GoLive, RecordAnalyticsEvent, RecordFinancePayment}
  alias Palee.Application.Fiscal.PaymentDocuments
  alias Palee.Finance

  @doc """
  ADR-184: refused with `:business_not_activated` when a business in demo
  mode would take money from anyone but one of its mock people.
  """
  def call(context, user_id, admin_id, params) do
    with :ok <- desk_method(params),
         :ok <- GoLive.check_payment(context, user_id),
         {:ok, received} <- call(user_id, admin_id, params) do
      # ADR-262: the legal document of the money received.
      {:ok, PaymentDocuments.attach(context, received, admin_id)}
    end
  end

  @doc """
  ADR-246: records money a payment provider confirmed (an online payment
  of an invoice). Idempotent through the payment's `idempotency_key`.
  """
  def record_online(context, user_id, params) do
    with :ok <- GoLive.check_payment(context, user_id),
         {:ok, received} <-
           Finance.with_tenant_context(context, fn ->
             call(user_id, nil, Map.put(params, "payment_method", "online"))
           end) do
      with_fiscal_document(context, received, nil)
    end
  end

  @doc """
  ADR-249: records a card tapped on the Viva.com Terminal app at the desk,
  after the provider confirmed it (`card_terminal`). Idempotent through the
  payment's `idempotency_key`; the document follows ADR-222. ADR-264: a
  card surcharge (`surcharge_cents`, recorded in Finance apart) goes on the
  same fiscal document, described as `surcharge_description`.
  """
  def record_terminal(context, user_id, params) do
    with :ok <- GoLive.check_payment(context, user_id),
         {:ok, received} <-
           Finance.with_tenant_context(context, fn ->
             call(
               user_id,
               params["created_by_id"],
               params
               |> Map.delete("surcharge_description")
               |> Map.put("payment_method", "card_terminal")
             )
           end) do
      received
      |> Map.merge(surcharge(params))
      |> then(&with_fiscal_document(context, &1, params["created_by_id"]))
    end
  end

  @doc """
  ADR-264: a walk-in's sale paid by Tap to Pay (no membership): the Finance
  stream invoice and payment `sale` (`Finance.record_stream_sale/2`,
  idempotent per its source) and its fiscal document (ADR-262), issued from
  that payment like any other.
  """
  def record_walk_in(context, sale, actor_id) do
    with :ok <- GoLive.check_payment(context, nil),
         {:ok, recorded} <- Finance.record_stream_sale(context, sale) do
      received = %{
        payment: recorded.payment,
        invoice: recorded.invoice,
        description: walk_in_description(recorded.invoice),
        amount_cents: recorded.payment.amount_cents,
        replayed: recorded.replayed
      }

      with_fiscal_document(context, received, actor_id)
    end
  end

  defp walk_in_description(%{lines: [%{description: description} | _]}), do: description
  defp walk_in_description(invoice), do: invoice[:invoice_number]

  defp surcharge(%{"surcharge_cents" => cents} = params) when is_integer(cents) and cents > 0,
    do: %{surcharge_cents: cents, surcharge_description: params["surcharge_description"]}

  defp surcharge(_params), do: %{}

  # ADR-262: money a provider confirmed is fulfilled only with its fiscal
  # document, so a failure makes the payment's fulfilment try again later.
  defp with_fiscal_document(context, received, actor_id) do
    case PaymentDocuments.issue(context, received, actor_id, DateTime.utc_now()) do
      {:ok, :not_configured} ->
        {:ok, Map.put(received, :fiscal_document, nil)}

      {:ok, document} ->
        {:ok, Map.put(received, :fiscal_document, PaymentDocuments.summary(document))}

      {:error, reason} ->
        {:error, {:fiscal_document_not_issued, reason}}
    end
  end

  # Staff never record a provider-confirmed method ("online",
  # "card_terminal") by hand.
  defp desk_method(params) do
    method = params["payment_method"] || params[:payment_method]

    if method in ["online", "card_terminal"],
      do: {:error, :invalid_payment_method},
      else: :ok
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
