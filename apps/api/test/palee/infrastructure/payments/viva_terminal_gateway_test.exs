defmodule Palee.Infrastructure.Payments.VivaTerminalGatewayTest do
  @moduledoc "ADR-249: the Viva.com Terminal adapter against stubbed Viva API answers."
  use ExUnit.Case, async: true

  alias Palee.Infrastructure.Payments.VivaTerminalGateway

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

  test "the sale request follows Viva's app-to-app Sale request" do
    request =
      VivaTerminalGateway.app_request(@account, %{
        reference: "pt1.abc.sig",
        amount_cents: 1_200,
        currency: "EUR",
        description: "Πακέτο 8 επισκέψεων",
        app_id: "app.palee.member",
        callback: "palee-terminal://result"
      })

    assert request.scheme == "vivapayclient://pay/v1"

    assert %{
             "appId" => "app.palee.member",
             "action" => "sale",
             "amount" => "1200",
             "clientTransactionId" => "pt1.abc.sig",
             "callback" => "palee-terminal://result",
             "paymentMethod" => "CardPresent",
             "customerTrns" => "Πακέτο 8 επισκέψεων"
           } = request.params

    # Never the ISV secret on a phone.
    refute Enum.any?(Map.keys(request.params), &String.starts_with?(&1, "ISV_"))
  end

  test "a transaction is confirmed with Viva's Retrieve Transaction, with its reference" do
    Req.Test.stub(Palee.PaymentsHttp, fn
      %{host: "demo-accounts.vivapayments.com"} = conn ->
        token(conn)

      %{host: "demo-api.vivapayments.com", request_path: "/checkout/v2/transactions/tx-1"} = conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer tok"]

        Req.Test.json(conn, %{
          "statusId" => "F",
          "amount" => 12.0,
          "currencyCode" => "978",
          "orderCode" => 3_050_112_220_001_919,
          "merchantTrns" => "pt1.abc.sig",
          "insDate" => "2027-02-06T12:00:00.12+02:00",
          "cardNumber" => "515876XXXXXX4490"
        })
    end)

    assert {:ok, transaction} = VivaTerminalGateway.confirm(@account, "tx-1")
    assert transaction.status == :succeeded
    assert transaction.amount_cents == 1_200
    assert transaction.currency == "EUR"
    assert transaction.reference == "pt1.abc.sig"
    assert transaction.created_at == ~U[2027-02-06 10:00:00.12Z]
    assert transaction.card.last4 == "4490"
    refute Map.has_key?(transaction, :method_token)
  end

  test "an unknown transaction and an outage are errors, never a payment" do
    Req.Test.stub(Palee.PaymentsHttp, fn
      %{host: "demo-accounts.vivapayments.com"} = conn ->
        token(conn)

      %{request_path: "/checkout/v2/transactions/missing"} = conn ->
        Plug.Conn.send_resp(conn, 404, "")

      %{request_path: "/checkout/v2/transactions/down"} = conn ->
        Plug.Conn.send_resp(conn, 503, "")
    end)

    assert VivaTerminalGateway.confirm(@account, "missing") ==
             {:error, {:invalid, :unknown_transaction}}

    assert {:error, {:transient, _}} = VivaTerminalGateway.confirm(@account, "down")
  end

  test "a lost result is found among the day's transactions by its reference" do
    Req.Test.stub(Palee.PaymentsHttp, fn
      %{host: "demo.vivapayments.com", request_path: "/api/transactions"} = conn ->
        assert conn.query_params["date"] == "2027-02-06"
        assert ["Basic " <> basic] = Plug.Conn.get_req_header(conn, "authorization")
        assert Base.decode64!(basic) == "mid:akey"

        Req.Test.json(conn, %{
          "Transactions" => [
            %{"TransactionId" => "tx-other", "MerchantTrns" => "pt1.other", "StatusId" => "F"},
            %{"TransactionId" => "tx-mine", "MerchantTrns" => "pt1.mine", "StatusId" => "F"}
          ],
          "ErrorCode" => 0
        })

      %{host: "demo-accounts.vivapayments.com"} = conn ->
        token(conn)

      %{request_path: "/checkout/v2/transactions/tx-mine"} = conn ->
        Req.Test.json(conn, %{
          "statusId" => "F",
          "amount" => 30,
          "currencyCode" => "978",
          "merchantTrns" => "pt1.mine"
        })
    end)

    assert {:ok, %{transaction_id: "tx-mine", status: :succeeded, amount_cents: 3_000}} =
             VivaTerminalGateway.find_by_reference(@account, "pt1.mine", ~D[2027-02-06])

    assert VivaTerminalGateway.find_by_reference(@account, "pt1.none", ~D[2027-02-06]) ==
             {:ok, nil}
  end
end
