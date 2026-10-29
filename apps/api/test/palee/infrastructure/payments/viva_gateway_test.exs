defmodule Palee.Infrastructure.Payments.VivaGatewayTest do
  @moduledoc "ADR-246: the Viva adapter against stubbed Viva API answers."
  use ExUnit.Case, async: true

  alias Palee.Infrastructure.Payments.VivaGateway

  @account %{
    provider: "viva",
    environment: "test",
    credentials: %{
      "client_id" => "cid",
      "client_secret" => "csecret",
      "merchant_id" => "mid",
      "api_key" => "akey"
    },
    settings: %{"source_code" => "1234"}
  }

  defp token(conn), do: Req.Test.json(conn, %{"access_token" => "tok", "expires_in" => 3600})

  test "a checkout order becomes a redirect to Viva's Smart Checkout" do
    Req.Test.stub(Palee.PaymentsHttp, fn
      %{host: "demo-accounts.vivapayments.com"} = conn ->
        assert ["Basic " <> basic] = Plug.Conn.get_req_header(conn, "authorization")
        assert Base.decode64!(basic) == "cid:csecret"
        token(conn)

      %{host: "demo-api.vivapayments.com", request_path: "/checkout/v2/orders"} = conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        order = Jason.decode!(body)
        assert order["amount"] == 6_500
        assert order["allowRecurring"] == true
        assert order["sourceCode"] == "1234"
        assert order["merchantTrns"] == "intent-1"
        assert order["customer"]["requestLang"] == "el-GR"
        Req.Test.json(conn, %{"orderCode" => 1_272_214_778_972_604})
    end)

    request = %{
      reference: "intent-1",
      amount_cents: 6_500,
      currency: "EUR",
      description: "INV-1",
      customer: %{email: "a@b.gr", language: "el"},
      save_method: true,
      return_url: "https://palee.test/r",
      cancel_url: "https://palee.test/r",
      expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second),
      idempotency_key: "k"
    }

    assert VivaGateway.create_checkout(@account, request) ==
             {:ok,
              %{
                provider_ref: "1272214778972604",
                redirect_url: "https://demo.vivapayments.com/web/checkout?ref=1272214778972604"
              }}
  end

  test "a transaction is read back and must belong to the order" do
    Req.Test.stub(Palee.PaymentsHttp, fn
      %{host: "demo-accounts.vivapayments.com"} = conn ->
        token(conn)

      %{request_path: "/checkout/v2/transactions/t-1"} = conn ->
        Req.Test.json(conn, %{
          "statusId" => "F",
          "orderCode" => 777,
          "amount" => 65.0,
          "currencyCode" => "978",
          "cardNumber" => "414746XXXXXX0133"
        })
    end)

    assert {:ok, payment} =
             VivaGateway.fetch_payment(@account, %{provider_ref: "777", transaction_id: "t-1"})

    assert payment.status == :succeeded
    assert payment.amount_cents == 6_500
    assert payment.currency == "EUR"
    assert payment.card.last4 == "0133"
    assert payment.method_token == "t-1"

    assert VivaGateway.fetch_payment(@account, %{provider_ref: "778", transaction_id: "t-1"}) ==
             {:error, {:invalid, :order_mismatch}}
  end

  test "refused OAuth credentials are reported as unauthorized" do
    Req.Test.stub(Palee.PaymentsHttp, fn conn ->
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_client"})
    end)

    assert VivaGateway.check(@account) == {:error, {:unauthorized, :oauth}}
  end

  test "a recurring charge that Viva refuses is a decline" do
    Req.Test.stub(Palee.PaymentsHttp, fn conn ->
      assert conn.request_path == "/api/transactions/t-1"

      Req.Test.json(conn, %{
        "ErrorCode" => 10_051,
        "ErrorText" => "Insufficient funds",
        "StatusId" => "E"
      })
    end)

    request = %{
      reference: "i",
      amount_cents: 100,
      currency: "EUR",
      description: "d",
      idempotency_key: "k"
    }

    assert VivaGateway.charge_saved(@account, "t-1", request) ==
             {:error, {:declined, "10051", "Insufficient funds"}}
  end

  test "the webhook URL check returns the account's key; a notification names the order" do
    Req.Test.stub(Palee.PaymentsHttp, fn conn ->
      assert conn.request_path == "/api/messages/config/token"
      Req.Test.json(conn, %{"Key" => "verification-key"})
    end)

    assert VivaGateway.parse_webhook(@account, %{method: "GET"}) ==
             {:reply, 200, %{"Key" => "verification-key"}}

    body =
      Jason.encode!(%{
        "EventTypeId" => 1796,
        "MessageId" => "m-1",
        "EventData" => %{"OrderCode" => 777, "TransactionId" => "t-1"}
      })

    assert {:ok, [%{event_id: "m-1", provider_ref: "777", transaction_id: "t-1"}]} =
             VivaGateway.parse_webhook(@account, %{method: "POST", body: body})
  end
end
