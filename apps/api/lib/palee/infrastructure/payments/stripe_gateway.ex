defmodule Palee.Infrastructure.Payments.StripeGateway do
  @moduledoc """
  Stripe (ADR-246): Checkout Sessions for the payer's first payment (with
  `setup_future_usage=off_session` when the card is saved), off-session
  PaymentIntents for later charges, refunds, and signed webhooks.

  Credentials (the business's own Stripe account): a secret or restricted
  key (`sk_…`/`rk_…`, whose test/live mode must match the environment)
  and the endpoint's `webhook_secret` (`whsec_…`). Every write carries an
  `Idempotency-Key`, so retrying after a timeout never charges twice.

  API version pinned in `@api_version`. Sources: docs.stripe.com (Checkout
  Sessions, PaymentIntents, Refunds, webhook signatures).
  """

  @behaviour Palee.Payments.Ports.Gateway

  alias Palee.Infrastructure.Payments.Http

  @base "https://api.stripe.com"
  @api_version "2024-06-20"
  @signature_tolerance 300
  @locales ~w(el en de fr it nl es)

  @impl true
  def credential_keys, do: ~w(secret_key webhook_secret)
  @impl true
  def setting_keys, do: []

  @impl true
  def check(account) do
    with :ok <- key_mode(account),
         {:ok, %{status: 200}} <- call(account, :get, "/v1/balance", []) do
      :ok
    else
      {:ok, response} -> {:error, error(response)}
      {:error, {:uncertain, reason}} -> {:error, {:transient, reason}}
      {:error, _reason} = error -> error
    end
  end

  defp key_mode(%{environment: environment, credentials: %{"secret_key" => key}})
       when is_binary(key) do
    test? = String.starts_with?(key, ["sk_test_", "rk_test_"])
    live? = String.starts_with?(key, ["sk_live_", "rk_live_"])

    cond do
      environment == "test" and test? -> :ok
      environment == "live" and live? -> :ok
      true -> {:error, {:invalid, :key_mode_mismatch}}
    end
  end

  defp key_mode(_account), do: {:error, {:unauthorized, :credentials_missing}}

  @impl true
  def create_checkout(account, request) do
    language = request.customer[:language]

    form =
      [
        mode: "payment",
        client_reference_id: request.reference,
        success_url: request.return_url,
        cancel_url: request.cancel_url,
        expires_at: DateTime.to_unix(request.expires_at),
        locale: if(language in @locales, do: language, else: "auto"),
        "line_items[0][quantity]": 1,
        "line_items[0][price_data][currency]": String.downcase(request.currency),
        "line_items[0][price_data][unit_amount]": request.amount_cents,
        "line_items[0][price_data][product_data][name]": request.description,
        "metadata[palee_intent_id]": request.reference,
        "payment_intent_data[metadata][palee_intent_id]": request.reference,
        "payment_intent_data[description]": request.description
      ]
      |> add(:customer_email, request.customer[:email])
      |> add_save(request.save_method)

    case call(account, :post, "/v1/checkout/sessions", form: form, key: request.idempotency_key) do
      {:ok, %{status: 200, body: %{"id" => id, "url" => url}}} ->
        {:ok, %{provider_ref: id, redirect_url: url}}

      {:ok, response} ->
        {:error, error(response)}

      {:error, {:uncertain, reason}} ->
        {:error, {:transient, reason}}

      {:error, _reason} = error ->
        error
    end
  end

  defp add_save(form, true),
    do:
      form ++
        ["payment_intent_data[setup_future_usage]": "off_session", customer_creation: "always"]

  defp add_save(form, _save), do: form

  @impl true
  def fetch_payment(account, %{provider_ref: "cs_" <> _rest = id}) do
    case call(account, :get, "/v1/checkout/sessions/" <> id,
           params: ["expand[]": "payment_intent.payment_method"]
         ) do
      {:ok, %{status: 200, body: session}} -> {:ok, session_payment(session)}
      {:ok, response} -> {:error, error(response)}
      {:error, {:uncertain, reason}} -> {:error, {:transient, reason}}
      {:error, _reason} = error -> error
    end
  end

  def fetch_payment(account, query) do
    case query[:transaction_id] || query[:provider_ref] do
      "pi_" <> _rest = id ->
        case call(account, :get, "/v1/payment_intents/" <> id,
               params: ["expand[]": "payment_method"]
             ) do
          {:ok, %{status: 200, body: intent}} -> {:ok, intent_payment(intent, nil)}
          {:ok, response} -> {:error, error(response)}
          {:error, {:uncertain, reason}} -> {:error, {:transient, reason}}
          {:error, _reason} = error -> error
        end

      _other ->
        {:error, {:invalid, :unknown_reference}}
    end
  end

  defp session_payment(session) do
    intent = if is_map(session["payment_intent"]), do: session["payment_intent"], else: %{}
    base = intent_payment(intent, session["customer"])

    status =
      cond do
        session["status"] == "complete" and session["payment_status"] == "paid" -> :succeeded
        session["status"] == "expired" -> :cancelled
        true -> :pending
      end

    %{
      base
      | status: status,
        amount_cents: session["amount_total"],
        currency: session["currency"] && String.upcase(session["currency"])
    }
  end

  defp intent_payment(intent, customer) do
    method = if is_map(intent["payment_method"]), do: intent["payment_method"], else: %{}
    card = method["card"] || %{}
    customer = customer || intent["customer"]
    customer = if is_map(customer), do: customer["id"], else: customer

    %{
      status: intent_status(intent),
      transaction_id: intent["id"],
      amount_cents: intent["amount"],
      currency: intent["currency"] && String.upcase(intent["currency"]),
      card:
        if(card == %{},
          do: nil,
          else: %{
            brand: card["brand"],
            last4: card["last4"],
            exp_month: card["exp_month"],
            exp_year: card["exp_year"]
          }
        ),
      method_token:
        if(
          is_binary(customer) and is_binary(method["id"]) and
            intent["setup_future_usage"] == "off_session",
          do: customer <> "|" <> method["id"]
        ),
      failure:
        case intent["last_payment_error"] do
          %{} = failure ->
            %{
              code: failure["decline_code"] || failure["code"] || "failed",
              message: failure["message"]
            }

          _none ->
            nil
        end
    }
  end

  defp intent_status(%{"status" => "succeeded"}), do: :succeeded
  defp intent_status(%{"status" => "canceled"}), do: :cancelled

  defp intent_status(%{"status" => "requires_payment_method", "last_payment_error" => %{}}),
    do: :failed

  defp intent_status(_intent), do: :pending

  @impl true
  def charge_saved(account, token, request) do
    case String.split(token, "|", parts: 2) do
      [customer, method] ->
        form = [
          amount: request.amount_cents,
          currency: String.downcase(request.currency),
          customer: customer,
          payment_method: method,
          off_session: true,
          confirm: true,
          description: request.description,
          "metadata[palee_intent_id]": request.reference
        ]

        case call(account, :post, "/v1/payment_intents", form: form, key: request.idempotency_key) do
          {:ok, %{status: 200, body: intent}} ->
            {:ok, intent_payment(intent, customer)}

          {:ok, %{status: 402, body: %{"error" => failure}}} ->
            {:error,
             {:declined, failure["decline_code"] || failure["code"] || "card_declined",
              failure["message"]}}

          {:ok, response} ->
            {:error, error(response)}

          {:error, {:uncertain, reason}} ->
            # The idempotency key makes a retry safe.
            {:error, {:transient, reason}}

          {:error, _reason} = error ->
            error
        end

      _bad ->
        {:error, {:invalid, :unknown_token}}
    end
  end

  @impl true
  def refund(account, request) do
    form = [payment_intent: request.transaction_id, amount: request.amount_cents]

    case call(account, :post, "/v1/refunds", form: form, key: request.idempotency_key) do
      {:ok, %{status: 200, body: %{"id" => id, "status" => "succeeded"}}} ->
        {:ok, %{provider_ref: id, status: :succeeded}}

      {:ok, %{status: 200, body: %{"id" => id, "status" => "pending"}}} ->
        {:ok, %{provider_ref: id, status: :pending}}

      {:ok, %{status: 200, body: body}} ->
        {:error, {:declined, "refund_#{body["status"]}", body["failure_reason"]}}

      {:ok, response} ->
        {:error, error(response)}

      {:error, {:uncertain, reason}} ->
        {:error, {:transient, reason}}

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def parse_webhook(account, %{method: "POST", headers: headers, body: body, now: now}) do
    with secret when is_binary(secret) <- account.credentials["webhook_secret"],
         header when is_binary(header) <- Http.header(headers, "stripe-signature"),
         :ok <- verify_signature(header, body, secret, now) do
      case Jason.decode(body) do
        {:ok, %{"id" => id, "type" => type, "data" => %{"object" => object}}} ->
          {:ok, [Map.merge(%{event_id: id, type: type}, references(object))]}

        _other ->
          {:error, :invalid_payload}
      end
    else
      _bad -> {:error, :invalid_signature}
    end
  end

  def parse_webhook(_account, _request), do: {:error, :invalid_payload}

  defp references(%{"object" => "checkout.session"} = session) do
    intent = session["payment_intent"]
    %{provider_ref: session["id"], transaction_id: if(is_binary(intent), do: intent)}
  end

  defp references(%{"object" => "payment_intent", "id" => id}),
    do: %{provider_ref: id, transaction_id: id}

  defp references(%{"object" => object} = data) when object in ["charge", "refund"],
    do: %{provider_ref: data["payment_intent"], transaction_id: data["payment_intent"]}

  defp references(_object), do: %{provider_ref: nil, transaction_id: nil}

  @doc "Checks a `Stripe-Signature` header (`t=…,v1=…`) within the tolerance."
  def verify_signature(header, body, secret, %DateTime{} = now) do
    parts =
      header
      |> String.split(",")
      |> Enum.map(&String.split(String.trim(&1), "=", parts: 2))
      |> Enum.filter(&match?([_key, _value], &1))

    timestamp = Enum.find_value(parts, fn [key, value] -> key == "t" && value end)

    with true <- is_binary(timestamp),
         {seconds, ""} <- Integer.parse(timestamp),
         true <- abs(DateTime.to_unix(now) - seconds) <= @signature_tolerance do
      expected =
        :hmac
        |> :crypto.mac(:sha256, secret, "#{seconds}.#{body}")
        |> Base.encode16(case: :lower)

      if Enum.any?(parts, fn [key, value] ->
           key == "v1" and Plug.Crypto.secure_compare(value, expected)
         end),
         do: :ok,
         else: {:error, :invalid_signature}
    else
      _invalid -> {:error, :invalid_signature}
    end
  end

  defp call(account, method, path, options) do
    {key, options} = Keyword.pop(options, :key)

    headers =
      [{"stripe-version", @api_version}] ++ if(key, do: [{"idempotency-key", key}], else: [])

    Http.request(
      [
        method: method,
        url: @base <> path,
        auth: {:bearer, account.credentials["secret_key"] || ""},
        headers: headers
      ] ++ options
    )
  end

  defp error(%Req.Response{status: status}) when status in [401, 403],
    do: {:unauthorized, {:http, status}}

  defp error(%Req.Response{status: status}) when status == 429 or status >= 500,
    do: {:transient, {:http, status}}

  defp error(%Req.Response{status: status, body: body}) do
    message = if is_map(body), do: get_in(body, ["error", "message"])
    {:invalid, {:http, status, message}}
  end

  defp add(form, _key, nil), do: form
  defp add(form, key, value), do: form ++ [{key, value}]
end
