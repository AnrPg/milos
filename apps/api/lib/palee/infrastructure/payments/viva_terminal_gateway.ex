defmodule Palee.Infrastructure.Payments.VivaTerminalGateway do
  @moduledoc """
  The «Viva.com Terminal» app on a staff phone (ADR-249): Tap to Pay on
  iPhone and Android, driven app-to-app (Android intent, iOS URL scheme
  `vivapayclient://pay/v1`), answering on Palee's callback URI.

  The phone's answer is never trusted: `confirm/2` reads the transaction
  back with `VivaGateway.fetch_payment/2` (Retrieve Transaction, OAuth with
  the business's own credentials). `find_by_reference/3` looks through the
  day's transactions (legacy API, basic auth) for a request whose result
  never reached the phone.

  No ISV fields: the sale goes to the business's own Viva account and
  Palee takes no fee through Viva.

  Written from Viva's public documentation (see ADR-249); to be confirmed
  with Viva's demo Terminal app before the first box.
  """

  @behaviour Palee.Payments.Ports.TerminalGateway

  alias Palee.Infrastructure.Payments.{Http, VivaGateway}

  @scheme "vivapayclient://pay/v1"
  @legacy_hosts %{
    "test" => "https://demo.vivapayments.com",
    "live" => "https://www.vivapayments.com"
  }

  @impl true
  def app_request(_account, sale) do
    %{
      scheme: @scheme,
      params: %{
        "appId" => sale.app_id,
        "action" => "sale",
        "clientTransactionId" => sale.reference,
        "amount" => Integer.to_string(sale.amount_cents),
        "customerTrns" => sale.description,
        "callback" => sale.callback,
        "paymentMethod" => "CardPresent",
        "show_receipt" => "false",
        "show_transaction_result" => "true",
        "show_rating" => "false",
        # iOS: deprecated, any value is accepted.
        "merchantKey" => "palee"
      }
    }
  end

  @impl true
  def confirm(account, transaction_id) when is_binary(transaction_id) do
    case VivaGateway.fetch_payment(account, %{provider_ref: nil, transaction_id: transaction_id}) do
      {:ok, payment} -> {:ok, Map.delete(payment, :method_token)}
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def find_by_reference(account, reference, %Date{} = date) do
    credentials = account.credentials

    with {:ok, response} <-
           Http.request(
             method: :get,
             url: Map.fetch!(@legacy_hosts, account.environment) <> "/api/transactions",
             params: [date: Date.to_iso8601(date)],
             auth: {:basic, "#{credentials["merchant_id"]}:#{credentials["api_key"]}"}
           ),
         {:ok, %{status: 200, body: body}} <- Http.classify(response) do
      transactions = (is_map(body) && body["Transactions"]) || []

      case Enum.find(transactions, &(&1["MerchantTrns"] == reference)) do
        %{"TransactionId" => id} when is_binary(id) -> confirm(account, id)
        _none -> {:ok, nil}
      end
    else
      {:ok, %Req.Response{status: 404}} -> {:ok, nil}
      {:ok, %Req.Response{status: status}} -> {:error, {:invalid, {:http, status, nil}}}
      {:error, {:uncertain, reason}} -> {:error, {:transient, reason}}
      {:error, _reason} = error -> error
    end
  end
end
