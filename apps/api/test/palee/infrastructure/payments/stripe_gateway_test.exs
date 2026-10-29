defmodule Palee.Infrastructure.Payments.StripeGatewayTest do
  @moduledoc "ADR-246: the Stripe adapter against stubbed Stripe API answers."
  use ExUnit.Case, async: true

  alias Palee.Infrastructure.Payments.StripeGateway

  @now ~U[2027-02-04 10:00:00.000000Z]
  @account %{
    provider: "stripe",
    environment: "test",
    credentials: %{"secret_key" => "sk_test_abc", "webhook_secret" => "whsec_test"},
    settings: %{}
  }

  defp checkout_request do
    %{
      reference: "intent-1",
      amount_cents: 6_500,
      currency: "EUR",
      description: "INV-1 · Μηνιαία",
      customer: %{email: "a@b.gr", language: "el"},
      save_method: true,
      return_url: "https://palee.test/pay/return?payment=intent-1",
      cancel_url: "https://palee.test/pay/return?payment=intent-1&cancelled=1",
      expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second),
      idempotency_key: "palee-checkout-intent-1"
    }
  end

  test "a key in the wrong mode is refused before any call" do
    live = %{@account | environment: "live"}
    assert StripeGateway.check(live) == {:error, {:invalid, :key_mode_mismatch}}
  end

  test "a checkout session saves the card off-session and carries an idempotency key" do
    Req.Test.stub(Palee.PaymentsHttp, fn conn ->
      assert conn.request_path == "/v1/checkout/sessions"
      assert Plug.Conn.get_req_header(conn, "idempotency-key") == ["palee-checkout-intent-1"]
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sk_test_abc"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      form = URI.decode_query(body)
      assert form["payment_intent_data[setup_future_usage]"] == "off_session"
      assert form["line_items[0][price_data][unit_amount]"] == "6500"
      assert form["line_items[0][price_data][currency]"] == "eur"
      assert form["locale"] == "el"
      Req.Test.json(conn, %{"id" => "cs_test_1", "url" => "https://checkout.stripe.com/c/1"})
    end)

    assert StripeGateway.create_checkout(@account, checkout_request()) ==
             {:ok, %{provider_ref: "cs_test_1", redirect_url: "https://checkout.stripe.com/c/1"}}
  end

  test "a paid session reports the card and a reusable customer|method token" do
    Req.Test.stub(Palee.PaymentsHttp, fn conn ->
      assert conn.request_path == "/v1/checkout/sessions/cs_test_1"

      Req.Test.json(conn, %{
        "id" => "cs_test_1",
        "status" => "complete",
        "payment_status" => "paid",
        "amount_total" => 6_500,
        "currency" => "eur",
        "customer" => "cus_1",
        "payment_intent" => %{
          "id" => "pi_1",
          "status" => "succeeded",
          "setup_future_usage" => "off_session",
          "payment_method" => %{
            "id" => "pm_1",
            "card" => %{
              "brand" => "visa",
              "last4" => "4242",
              "exp_month" => 12,
              "exp_year" => 2030
            }
          }
        }
      })
    end)

    assert {:ok, payment} = StripeGateway.fetch_payment(@account, %{provider_ref: "cs_test_1"})
    assert payment.status == :succeeded
    assert payment.transaction_id == "pi_1"
    assert payment.amount_cents == 6_500
    assert payment.currency == "EUR"
    assert payment.method_token == "cus_1|pm_1"
    assert payment.card.last4 == "4242"
  end

  test "a declined off-session charge reports the decline code" do
    Req.Test.stub(Palee.PaymentsHttp, fn conn ->
      conn
      |> Plug.Conn.put_status(402)
      |> Req.Test.json(%{
        "error" => %{
          "code" => "card_declined",
          "decline_code" => "insufficient_funds",
          "message" => "No"
        }
      })
    end)

    request = %{
      reference: "i",
      amount_cents: 100,
      currency: "EUR",
      description: "d",
      idempotency_key: "k"
    }

    assert StripeGateway.charge_saved(@account, "cus_1|pm_1", request) ==
             {:error, {:declined, "insufficient_funds", "No"}}
  end

  test "webhooks are accepted only with a fresh valid signature" do
    body =
      Jason.encode!(%{
        "id" => "evt_1",
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => %{
            "object" => "checkout.session",
            "id" => "cs_1",
            "payment_intent" => "pi_1"
          }
        }
      })

    t = DateTime.to_unix(@now)

    signature =
      :crypto.mac(:hmac, :sha256, "whsec_test", "#{t}.#{body}") |> Base.encode16(case: :lower)

    request = %{
      method: "POST",
      body: body,
      now: @now,
      headers: [{"stripe-signature", "t=#{t},v1=#{signature}"}]
    }

    assert {:ok, [%{event_id: "evt_1", provider_ref: "cs_1", transaction_id: "pi_1"}]} =
             StripeGateway.parse_webhook(@account, request)

    assert StripeGateway.parse_webhook(@account, %{request | body: body <> " "}) ==
             {:error, :invalid_signature}

    late = %{request | now: DateTime.add(@now, 301, :second)}
    assert StripeGateway.parse_webhook(@account, late) == {:error, :invalid_signature}
  end
end
