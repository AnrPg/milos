defmodule Palee.Infrastructure.Fiscal.FiskalyEInvoiceNetworkTest do
  @moduledoc """
  ADR-250: the fiskaly E-INVOICE adapter's requests and how answers are
  read (Req.Test stub): token, the System's VAT codes, INTENTION then
  TRANSACTION records with derived idempotency keys, corrections, and the
  delivery read from the E_INVOICE::TRANSMISSION record.
  """

  use ExUnit.Case, async: false

  alias Palee.Infrastructure.Fiscal.{FiskalyEInvoiceNetwork, FiskalyUnified}

  @system "0190f8a2-0000-7000-8000-00000000e1e1"
  @connection %{
    environment: "test",
    provider: "fiskaly",
    api_key: "fk-key",
    api_secret: "fk-secret",
    legal_entity_id: @system
  }
  @guid "8a1c1f10-0000-4000-8000-000000000001"

  @document %{
    kind: "invoice",
    number: "F-2027-0001",
    issue_date: ~D[2027-02-08],
    issued_at: ~U[2027-02-08 10:00:00.000000Z],
    currency: "EUR",
    country_code: "BE",
    payment_method: "bank_transfer",
    buyer: %{
      "name" => "Entreprise Cliente SA",
      "vat_number" => "BE 0202.239.951",
      "street" => "Avenue Louise",
      "building_number" => "54",
      "postal_code" => "1050",
      "city" => "Ixelles",
      "country_code" => "BE"
    },
    net_cents: 3_000,
    tax_cents: 630,
    gross_cents: 3_630,
    tax_breakdown: [
      %{"rate_bp" => 2100, "net_cents" => 3_000, "tax_cents" => 630, "tax_category" => "standard"}
    ],
    lines: [
      %{
        position: 1,
        description: "Abonnement entreprise",
        quantity: 3,
        net_cents: 3_000,
        tax_cents: 630,
        gross_cents: 3_630,
        rate_bp: 2100,
        tax_category: "standard",
        exemption_reason: nil,
        source_type: nil
      }
    ]
  }

  @submission %{
    ubl: {"Invoice", []},
    document: @document,
    original: nil,
    document_type: "Invoice",
    idempotency_guid: @guid,
    recipient: %{scheme: "0208", identifier: "0202239951"}
  }

  defp stub(routes) do
    test_pid = self()

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:request, conn, body})

      case routes.(conn.method, conn.request_path, body) do
        {status, json} -> conn |> Plug.Conn.put_status(status) |> Req.Test.json(json)
        :timeout -> Req.Test.transport_error(conn, :timeout)
      end
    end)
  end

  defp fiskaly(transaction \\ fn _body -> {200, %{"content" => record("rec-tx", "ACCEPTED")}} end) do
    fn
      "POST", "/tokens", _body ->
        {200, %{"content" => %{"authentication" => %{"bearer" => "jwt-1"}}}}

      "GET", "/systems/" <> _id, _body ->
        {200,
         %{
           "content" => %{
             "id" => @system,
             "vat_rates" => [
               %{"code" => "STANDARD", "percentage" => "21.00"},
               %{"code" => "REDUCED_1", "percentage" => "12"},
               %{"code" => "REDUCED_2", "percentage" => "6.00"}
             ],
             "vat_exemptions" => [%{"code" => "CAUSE_1"}]
           }
         }}

      "POST", "/records", body ->
        case Jason.decode!(body) do
          %{"content" => %{"type" => "INTENTION"}} ->
            {200, %{"content" => record("rec-intention", "COMPLETED")}}

          %{"content" => %{"type" => "TRANSACTION"}} = decoded ->
            transaction.(decoded)
        end
    end
  end

  defp record(id, state, extra \\ %{}),
    do: Map.merge(%{"id" => id, "state" => state, "mode" => "PROCESSING"}, extra)

  defp requests do
    receive_all([])
  end

  defp receive_all(acc) do
    receive do
      {:request, conn, body} -> receive_all([{conn, body} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "submits INTENTION then TRANSACTION::INVOICE with derived idempotency keys" do
    stub(fiskaly())

    assert {{:ok, %{submission_id: "rec-tx"}}, wire} =
             FiskalyEInvoiceNetwork.submit(@connection, @submission)

    [{token, token_body}, {system, _}, {intention, intention_body}, {tx, tx_body}] = requests()

    assert token.request_path == "/tokens"
    assert Jason.decode!(token_body)["content"] == %{
             "type" => "API_KEY",
             "key" => "fk-key",
             "secret" => "fk-secret"
           }

    assert system.request_path == "/systems/" <> @system
    assert Plug.Conn.get_req_header(system, "authorization") == ["Bearer jwt-1"]
    assert Plug.Conn.get_req_header(system, "x-api-version") == [FiskalyUnified.version()]

    assert %{"type" => "INTENTION", "system" => %{"id" => @system}} =
             Jason.decode!(intention_body)["content"]

    assert Plug.Conn.get_req_header(intention, "x-idempotency-key") == [
             FiskalyUnified.idempotency_key("einvoice:#{@guid}:intention")
           ]

    assert Plug.Conn.get_req_header(tx, "x-idempotency-key") == [
             FiskalyUnified.idempotency_key("einvoice:#{@guid}:transaction")
           ]

    content = Jason.decode!(tx_body)["content"]
    assert content["record"] == %{"id" => "rec-intention"}
    operation = content["operation"]
    assert operation["type"] == "INVOICE"
    assert operation["document"]["number"] == "F-2027-0001"
    assert operation["document"]["issued_at"] == "2027-02-08T10:00:00+00:00"
    assert operation["totals"]["vat"] == %{"amount" => "6.30", "exclusive" => "30.00", "inclusive" => "36.30"}

    assert [%{"type" => "VAT_RATE", "code" => "STANDARD", "percentage" => "21.00"}] =
             operation["breakdown"]

    [entry] = operation["entries"]
    assert entry["type"] == "SALE"
    assert entry["data"]["unit"] == %{"quantity" => "3", "price" => %{"exclusive" => "10.00", "inclusive" => "12.10"}}
    assert entry["data"]["vat"]["code"] == "STANDARD"

    [recipient] = operation["recipients"]
    assert recipient["type"] == "BUSINESS"
    assert recipient["identification"] == %{"type" => "VAT", "number" => "BE0202239951"}
    assert recipient["invoicing"] == %{"type" => "PEPPOL", "identifier" => "0208:0202239951"}
    assert [%{"type" => "OUTSTANDING", "concept" => "INVOICE"}] = operation["payments"]

    # The attempt log has the document, never the credentials or the token.
    assert wire.request_body =~ "F-2027-0001"
    refute inspect(wire) =~ "fk-secret"
    refute inspect(wire) =~ "fk-key"
    refute inspect(wire) =~ "jwt-1"
  end

  test "the same GUID gives the same keys, so a staff retry is a replay" do
    assert FiskalyUnified.idempotency_key("einvoice:a:transaction") ==
             FiskalyUnified.idempotency_key("einvoice:a:transaction")

    refute FiskalyUnified.idempotency_key("einvoice:a:transaction") ==
             FiskalyUnified.idempotency_key("einvoice:b:transaction")

    assert FiskalyUnified.idempotency_key("x") =~
             ~r/^[0-9a-f]{8}-[0-9a-f]{4}-3[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  end

  test "a credit note is a CORRECTION of the invoice's record with RETURN entries" do
    stub(fiskaly())

    credit = %{@document | kind: "credit_note", number: "C-2027-0001", payment_method: "cash"}

    assert {{:ok, %{submission_id: "rec-tx"}}, _wire} =
             FiskalyEInvoiceNetwork.submit(@connection, %{
               @submission
               | document: credit,
                 document_type: "CreditNote",
                 original: %{number: "F-2027-0001", issue_date: ~D[2027-02-08], submission_id: "rec-1"}
             })

    {_tx, body} = List.last(requests())
    operation = Jason.decode!(body)["content"]["operation"]
    assert operation["type"] == "CORRECTION"
    assert operation["record"] == %{"id" => "rec-1"}
    assert operation["data"]["type"] == "INVOICE"
    assert [%{"type" => "RETURN"}] = operation["data"]["entries"]
    assert [%{"type" => "CASH", "details" => %{"amount" => "36.30"}}] = operation["data"]["payments"]

    # Without the invoice's record at fiskaly, no record is created.
    stub(fiskaly(fn _body -> flunk("no transaction expected") end))

    assert {{:error, {:rejected, [%{code: "original_not_sent"}]}}, _} =
             FiskalyEInvoiceNetwork.submit(@connection, %{@submission | document: credit})
  end

  test "rejections, refused credentials, timeouts and reused keys" do
    stub(
      fiskaly(fn _body ->
        {200,
         %{
           "content" =>
             record("rec-tx", "REJECTED", %{
               "logs" => [%{"severity" => "ERROR", "message" => "Recipient not on Peppol"}]
             })
         }}
      end)
    )

    assert {{:error, {:rejected, [%{code: "rejected", message: "Recipient not on Peppol"}]}}, _} =
             FiskalyEInvoiceNetwork.submit(@connection, @submission)

    stub(fiskaly(fn _body -> {400, %{"code" => "E_BAD_REQUEST", "message" => "number"}} end))

    assert {{:error, {:rejected, [%{code: "E_BAD_REQUEST"}]}}, _} =
             FiskalyEInvoiceNetwork.submit(@connection, @submission)

    stub(fiskaly(fn _body -> {422, %{"code" => "E_IDEMPOTENCY", "message" => "Idempotency key mismatch"}} end))

    assert {{:error, {:uncertain, :idempotency_key_reused}}, _} =
             FiskalyEInvoiceNetwork.submit(@connection, @submission)

    stub(fiskaly(fn _body -> {409, %{"code" => "E_CONFLICT", "message" => "processing"}} end))

    assert {{:error, {:uncertain, :in_progress}}, _} =
             FiskalyEInvoiceNetwork.submit(@connection, @submission)

    stub(fiskaly(fn _body -> :timeout end))
    assert {{:error, {:uncertain, _}}, _} = FiskalyEInvoiceNetwork.submit(@connection, @submission)

    stub(fn "POST", "/tokens", _body -> {401, %{"code" => "E_UNAUTHORIZED"}} end)

    assert {{:error, {:unauthorized, _}}, _} =
             FiskalyEInvoiceNetwork.submit(@connection, @submission)
  end

  test "missing credentials or System never reach the network" do
    stub(fn _method, _path, _body -> flunk("no request expected") end)

    assert {{:error, {:unauthorized, :credentials_missing}}, _} =
             FiskalyEInvoiceNetwork.submit(%{@connection | api_secret: nil}, @submission)

    assert {{:error, {:unauthorized, :system_missing}}, _} =
             FiskalyEInvoiceNetwork.submit(%{@connection | legal_entity_id: nil}, @submission)
  end

  test "a VAT rate the System does not know is refused before sending" do
    stub(fiskaly(fn _body -> flunk("no transaction expected") end))

    odd = %{
      @document
      | lines: [%{hd(@document.lines) | rate_bp: 1700}],
        tax_breakdown: [%{"rate_bp" => 1700, "net_cents" => 3_000, "tax_cents" => 510}]
    }

    assert {{:error, {:rejected, [%{code: "vat_rate_unmapped"}]}}, _} =
             FiskalyEInvoiceNetwork.submit(@connection, %{@submission | document: odd})
  end

  test "delivery is read from the transmission record" do
    stub(fn
      "POST", "/tokens", _ -> {200, %{"content" => %{"authentication" => %{"bearer" => "jwt"}}}}
      "GET", "/records/rec-tx", _ -> {200, %{"content" => record("rec-tx", "ACCEPTED")}}
    end)

    assert {{:ok, :in_progress}, _} = FiskalyEInvoiceNetwork.status(@connection, "rec-tx")

    stub(fn
      "POST", "/tokens", _ ->
        {200, %{"content" => %{"authentication" => %{"bearer" => "jwt"}}}}

      "GET", "/records/rec-tx", _ ->
        {200,
         %{"content" => record("rec-tx", "COMPLETED", %{"used_in" => %{"id" => "rec-transmission"}})}}

      "GET", "/records/rec-transmission", _ ->
        {200,
         %{"content" => %{"id" => "rec-transmission", "state" => "COMPLETED", "mode" => "FINISHED"}}}
    end)

    assert {{:ok, :delivered}, _} = FiskalyEInvoiceNetwork.status(@connection, "rec-tx")

    stub(fn
      "POST", "/tokens", _ ->
        {200, %{"content" => %{"authentication" => %{"bearer" => "jwt"}}}}

      "GET", "/records/rec-tx", _ ->
        {200,
         %{"content" => record("rec-tx", "COMPLETED", %{"used_in" => %{"id" => "rec-transmission"}})}}

      "GET", "/records/rec-transmission", _ ->
        {200,
         %{
           "content" => %{
             "state" => "FAILED",
             "mode" => "FINISHED",
             "logs" => [%{"severity" => "ERROR", "message" => "Receiver access point refused"}]
           }
         }}
    end)

    assert {{:ok, {:failed, [%{message: "Receiver access point refused"}]}}, _} =
             FiskalyEInvoiceNetwork.status(@connection, "rec-tx")

    # A read is safe to repeat: a timeout is transient, not uncertain.
    stub(fn
      "POST", "/tokens", _ -> {200, %{"content" => %{"authentication" => %{"bearer" => "jwt"}}}}
      "GET", _path, _ -> :timeout
    end)

    assert {{:error, {:transient, _}}, _} = FiskalyEInvoiceNetwork.status(@connection, "rec-tx")
  end
end
