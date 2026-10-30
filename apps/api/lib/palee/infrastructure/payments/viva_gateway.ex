defmodule Palee.Infrastructure.Payments.VivaGateway do
  @moduledoc """
  Viva (ADR-246): Smart Checkout for the payer's first payment, recurring
  charges by reference to that first transaction, refunds and webhooks.

  Credentials (the business's own Viva account): OAuth `client_id` and
  `client_secret` (Smart Checkout API), `merchant_id` and `api_key`
  (basic auth for recurring charges, refunds and the webhook key). Setting:
  the payment source `source_code`, whose success and failure URLs in the
  Viva dashboard point to Palee's return page.

  Viva does not sign webhooks: every notification is only a hint, and the
  transaction is read back from Viva before anything is recorded.

  Recurring charges and refunds have no idempotency key at Viva, so a
  request that may have reached Viva (a timeout) is reported as
  `{:uncertain, _}` and never sent again automatically.

  Written from Viva's public developer documentation (see ADR-246); to be
  confirmed against Viva's demo environment before the first live box.
  """

  @behaviour Palee.Payments.Ports.Gateway

  alias Palee.Infrastructure.Payments.Http

  @hosts %{
    "test" => %{
      accounts: "https://demo-accounts.vivapayments.com",
      api: "https://demo-api.vivapayments.com",
      legacy: "https://demo.vivapayments.com"
    },
    "live" => %{
      accounts: "https://accounts.vivapayments.com",
      api: "https://api.vivapayments.com",
      legacy: "https://www.vivapayments.com"
    }
  }
  @languages %{
    "el" => "el-GR",
    "en" => "en-GB",
    "de" => "de-DE",
    "fr" => "fr-FR",
    "it" => "it-IT",
    "nl" => "nl-NL",
    "es" => "es-ES"
  }

  @impl true
  def credential_keys, do: ~w(client_id client_secret merchant_id api_key)
  @impl true
  def setting_keys, do: ~w(source_code)

  defp host(account, which), do: @hosts |> Map.fetch!(account.environment) |> Map.fetch!(which)

  @impl true
  def check(account) do
    with {:ok, _token} <- access_token(account),
         {:ok, _key} <- webhook_key(account) do
      :ok
    end
  end

  @impl true
  def create_checkout(account, request) do
    body =
      drop_nils(%{
        amount: request.amount_cents,
        customerTrns: request.description,
        merchantTrns: request.reference,
        paymentTimeout: max(DateTime.diff(request.expires_at, DateTime.utc_now(), :second), 300),
        allowRecurring: request.save_method,
        sourceCode: account.settings["source_code"],
        tags: ["palee"],
        customer: %{
          email: request.customer[:email],
          fullName: request.customer[:name],
          requestLang: Map.get(@languages, request.customer[:language], "en-GB")
        }
      })

    with {:ok, token} <- access_token(account),
         {:ok, response} <-
           Http.request(
             method: :post,
             url: host(account, :api) <> "/checkout/v2/orders",
             auth: {:bearer, token},
             json: body
           ),
         {:ok, %{status: 200, body: %{"orderCode" => code}}} <- Http.classify(response) do
      ref = to_string(code)

      {:ok,
       %{provider_ref: ref, redirect_url: host(account, :legacy) <> "/web/checkout?ref=" <> ref}}
    else
      {:ok, %Req.Response{} = response} -> {:error, {:invalid, error_of(response)}}
      {:error, {:uncertain, reason}} -> {:error, {:transient, reason}}
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def fetch_payment(account, %{transaction_id: transaction_id} = query)
      when is_binary(transaction_id) and transaction_id != "" do
    with {:ok, token} <- access_token(account),
         {:ok, response} <-
           Http.request(
             method: :get,
             url:
               host(account, :api) <>
                 "/checkout/v2/transactions/" <> URI.encode_www_form(transaction_id),
             auth: {:bearer, token}
           ),
         {:ok, %{status: 200, body: body}} when is_map(body) <- Http.classify(response) do
      order = body["orderCode"] && to_string(body["orderCode"])

      if query[:provider_ref] && order && order != query.provider_ref do
        {:error, {:invalid, :order_mismatch}}
      else
        {:ok,
         %{
           status: status(body["statusId"]),
           transaction_id: transaction_id,
           amount_cents: Http.cents(body["amount"]),
           currency: Http.currency_from_numeric(body["currencyCode"]),
           card: %{
             brand: body["cardType"] || body["cardBrand"],
             last4: Http.last4(body["cardNumber"]),
             exp_month: nil,
             exp_year: nil
           },
           method_token: transaction_id,
           failure: failure(body["statusId"], body["errorText"]),
           # ADR-249: the merchant reference and time, to tie a terminal sale to its request.
           reference: body["merchantTrns"],
           created_at: parse_time(body["insDate"]),
           # ADR-264: the parts of `amount` that are a tip and a card surcharge.
           tip_cents: Http.cents(body["tipAmount"]) || 0,
           surcharge_cents: Http.cents(body["surchargeAmount"]) || 0
         }}
      end
    else
      {:ok, %Req.Response{status: 404}} -> {:error, {:invalid, :unknown_transaction}}
      {:ok, %Req.Response{} = response} -> {:error, {:invalid, error_of(response)}}
      {:error, {:uncertain, reason}} -> {:error, {:transient, reason}}
      {:error, _reason} = error -> error
    end
  end

  def fetch_payment(account, %{provider_ref: ref}) when is_binary(ref) do
    # No transaction id yet: look for one paid against the order.
    with {:ok, response} <-
           Http.request(
             method: :get,
             url: host(account, :legacy) <> "/api/transactions",
             params: [ordercode: ref],
             auth: basic(account)
           ),
         {:ok, %{status: 200, body: body}} <- Http.classify(response) do
      transactions = (is_map(body) && body["Transactions"]) || []

      case Enum.find(transactions, &(&1["StatusId"] == "F")) do
        %{"TransactionId" => id} ->
          fetch_payment(account, %{provider_ref: ref, transaction_id: id})

        nil ->
          {:ok, %{status: :pending, transaction_id: nil}}
      end
    else
      {:ok, %Req.Response{status: 404}} -> {:ok, %{status: :pending, transaction_id: nil}}
      {:ok, %Req.Response{} = response} -> {:error, {:invalid, error_of(response)}}
      {:error, {:uncertain, reason}} -> {:error, {:transient, reason}}
      {:error, _reason} = error -> error
    end
  end

  def fetch_payment(_account, _query), do: {:error, {:invalid, :no_reference}}

  @impl true
  def charge_saved(account, initial_transaction_id, request) do
    with {:ok, response} <-
           Http.request(
             method: :post,
             url:
               host(account, :legacy) <>
                 "/api/transactions/" <> URI.encode_www_form(initial_transaction_id),
             auth: basic(account),
             json: %{
               amount: request.amount_cents,
               customerTrns: request.description,
               merchantTrns: request.reference,
               sourceCode: account.settings["source_code"]
             }
           ),
         {:ok, %{status: status, body: body}} when status in [200, 400] and is_map(body) <-
           Http.classify(response) do
      legacy_result(body, request)
    else
      {:ok, %Req.Response{} = response} -> {:error, {:invalid, error_of(response)}}
      {:error, _reason} = error -> error
    end
  end

  defp legacy_result(%{"ErrorCode" => code} = body, request) when code not in [0, nil] do
    if body["StatusId"] == "F",
      do: legacy_result(Map.delete(body, "ErrorCode"), request),
      else: {:error, {:declined, to_string(code), body["ErrorText"]}}
  end

  defp legacy_result(%{"StatusId" => "F", "TransactionId" => id}, request) do
    {:ok,
     %{
       status: :succeeded,
       transaction_id: id,
       amount_cents: request.amount_cents,
       currency: request.currency
     }}
  end

  defp legacy_result(%{"StatusId" => status, "TransactionId" => id} = body, _request) do
    {:ok,
     %{status: status(status), transaction_id: id, failure: failure(status, body["ErrorText"])}}
  end

  defp legacy_result(body, _request), do: {:error, {:invalid, inspect(body)}}

  @impl true
  def refund(account, request) do
    with {:ok, response} <-
           Http.request(
             method: :delete,
             url:
               host(account, :legacy) <>
                 "/api/transactions/" <> URI.encode_www_form(request.transaction_id),
             params: [amount: request.amount_cents, sourceCode: account.settings["source_code"]],
             auth: basic(account)
           ),
         {:ok, %{status: status, body: body}} when status in [200, 400] and is_map(body) <-
           Http.classify(response) do
      case legacy_result(body, request) do
        {:ok, %{status: :succeeded, transaction_id: id}} ->
          {:ok, %{provider_ref: id, status: :succeeded}}

        {:ok, %{transaction_id: id}} ->
          {:ok, %{provider_ref: id, status: :pending}}

        error ->
          error
      end
    else
      {:ok, %Req.Response{} = response} -> {:error, {:invalid, error_of(response)}}
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def parse_webhook(account, %{method: "GET"}) do
    # Viva checks a new webhook URL by asking it for the account's key.
    case webhook_key(account) do
      {:ok, key} -> {:reply, 200, %{"Key" => key}}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_webhook(_account, %{method: "POST", body: body}) do
    case Jason.decode(body) do
      {:ok, %{"EventData" => data} = event} when is_map(data) ->
        transaction = data["TransactionId"]
        type = to_string(event["EventTypeId"] || "unknown")

        {:ok,
         [
           %{
             event_id: to_string(event["MessageId"] || "#{type}:#{transaction}"),
             type: type,
             provider_ref: data["OrderCode"] && to_string(data["OrderCode"]),
             transaction_id: transaction,
             # ADR-249: a terminal sale is known by its merchant reference.
             reference: data["MerchantTrns"]
           }
         ]}

      _other ->
        {:error, :invalid_payload}
    end
  end

  def parse_webhook(_account, _request), do: {:error, :invalid_payload}

  # ── helpers ─────────────────────────────────────────────────────────────

  defp access_token(account) do
    credentials = account.credentials

    with {:ok, response} <-
           Http.request(
             method: :post,
             url: host(account, :accounts) <> "/connect/token",
             auth: {:basic, "#{credentials["client_id"]}:#{credentials["client_secret"]}"},
             form: [grant_type: "client_credentials"]
           ),
         {:ok, %{status: 200, body: %{"access_token" => token}}} <- Http.classify(response) do
      {:ok, token}
    else
      {:ok, %Req.Response{status: status}} when status in [400, 401] ->
        {:error, {:unauthorized, :oauth}}

      {:ok, %Req.Response{} = response} ->
        {:error, {:invalid, error_of(response)}}

      {:error, {:uncertain, reason}} ->
        {:error, {:transient, reason}}

      {:error, _reason} = error ->
        error
    end
  end

  defp webhook_key(account) do
    with {:ok, response} <-
           Http.request(
             method: :get,
             url: host(account, :legacy) <> "/api/messages/config/token",
             auth: basic(account)
           ),
         {:ok, %{status: 200, body: %{"Key" => key}}} <- Http.classify(response) do
      {:ok, key}
    else
      {:ok, %Req.Response{} = response} -> {:error, {:invalid, error_of(response)}}
      {:error, {:uncertain, reason}} -> {:error, {:transient, reason}}
      {:error, _reason} = error -> error
    end
  end

  defp basic(account),
    do: {:basic, "#{account.credentials["merchant_id"]}:#{account.credentials["api_key"]}"}

  # Viva transaction statuses: F finished, A in progress, E error,
  # X cancelled, R refunded (it was paid), M/MA/MI/ML/MW/MS claims.
  defp status("F"), do: :succeeded
  defp status("R"), do: :succeeded
  defp status("E"), do: :failed
  defp status("X"), do: :cancelled
  defp status(_other), do: :pending

  defp failure(status, text) when status in ["E", "X"],
    do: %{code: "viva_#{status}", message: text && to_string(text)}

  defp failure(_status, _text), do: nil

  defp error_of(%Req.Response{status: status, body: body}) do
    message =
      case body do
        %{"message" => message} -> message
        %{"ErrorText" => message} -> message
        _other -> nil
      end

    {:http, status, message}
  end

  defp parse_time(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> at
      _error -> nil
    end
  end

  defp parse_time(_text), do: nil

  defp drop_nils(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn
      {key, value} when is_map(value) -> {key, drop_nils(value)}
      pair -> pair
    end)
  end
end
