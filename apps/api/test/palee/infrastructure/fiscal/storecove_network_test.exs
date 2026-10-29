defmodule Palee.Infrastructure.Fiscal.StorecoveNetworkTest do
  @moduledoc "ADR-250: the Storecove adapter's requests and how answers are read (Req.Test stub)."

  use ExUnit.Case, async: false

  alias Palee.Infrastructure.Fiscal.StorecoveNetwork

  @connection %{api_key: "sc-key", legal_entity_id: "4711"}
  @request %{
    ubl: {"Invoice", [{"cbc:ID", "F-1 & <2>"}]},
    idempotency_guid: "8a1c1f10-0000-4000-8000-000000000001",
    recipient: %{scheme: "0208", identifier: "0123456749"}
  }

  setup do
    previous = Application.get_env(:palee, :storecove)
    Application.put_env(:palee, :storecove, base_url: "https://storecove.test/api/v2/")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:palee, :storecove, previous),
        else: Application.delete_env(:palee, :storecove)
    end)

    :ok
  end

  defp stub(fun) do
    test_pid = self()

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:request, conn, body})
      fun.(conn)
    end)
  end

  test "submits the UBL as raw document data with routing and idempotency GUID" do
    stub(&Req.Test.json(&1, %{"guid" => "sub-1"}))

    assert {{:ok, %{submission_id: "sub-1"}}, wire} =
             StorecoveNetwork.submit(@connection, @request)

    assert_received {:request, conn, body}

    assert conn.method == "POST"
    assert conn.request_path == "/api/v2/document_submissions"
    assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sc-key"]

    payload = Jason.decode!(body)
    assert payload["legalEntityId"] == 4711
    assert payload["idempotencyGuid"] == @request.idempotency_guid
    assert payload["routing"]["eIdentifiers"] == [%{"scheme" => "BE:EN", "id" => "0123456749"}]

    raw = payload["document"]["rawDocumentData"]
    assert %{"parse" => true, "parseStrategy" => "ubl"} = raw
    xml = Base.decode64!(raw["document"])
    assert xml =~ "<cbc:ID>F-1 &amp; &lt;2&gt;</cbc:ID>"

    # The wire log keeps the document, never the API key.
    refute inspect(wire) =~ "sc-key"
  end

  test "a duplicate GUID is uncertain, other 4xx are rejections, timeouts are uncertain" do
    stub(fn conn ->
      conn
      |> Plug.Conn.put_status(422)
      |> Req.Test.json(%{
        "errors" => [%{"source" => "idempotencyGuid", "details" => "already used"}]
      })
    end)

    assert {{:error, {:uncertain, :duplicate_idempotency_guid}}, _} =
             StorecoveNetwork.submit(@connection, @request)

    stub(fn conn ->
      conn
      |> Plug.Conn.put_status(422)
      |> Req.Test.json(%{"errors" => [%{"source" => "routing", "details" => "unknown receiver"}]})
    end)

    assert {{:error, {:rejected, [%{code: "routing", message: "unknown receiver"}]}}, _} =
             StorecoveNetwork.submit(@connection, @request)

    stub(&Req.Test.transport_error(&1, :timeout))
    assert {{:error, {:uncertain, _}}, _} = StorecoveNetwork.submit(@connection, @request)
  end

  test "missing credentials never reach the network" do
    stub(fn _conn -> flunk("no request expected") end)

    assert {{:error, {:unauthorized, :credentials_missing}}, _} =
             StorecoveNetwork.submit(%{@connection | api_key: nil}, @request)

    assert {{:error, {:unauthorized, :legal_entity_missing}}, _} =
             StorecoveNetwork.submit(%{api_key: "k"}, @request)
  end

  test "delivery is read from the sending evidence" do
    stub(fn conn -> conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{}) end)
    assert {{:ok, :in_progress}, _} = StorecoveNetwork.status(@connection, "sub-1")

    assert_received {:request,
                     %{
                       method: "GET",
                       request_path: "/api/v2/document_submissions/sub-1/evidence/sending"
                     }, _}

    stub(
      &Req.Test.json(&1, %{
        "receiver" => "0208:0123456749",
        "transmission_result" => "acknowledged"
      })
    )

    assert {{:ok, :delivered}, _} = StorecoveNetwork.status(@connection, "sub-1")

    stub(
      &Req.Test.json(&1, %{
        "status" => "failed",
        "errors" => [%{"code" => "x", "message" => "gone"}]
      })
    )

    assert {{:ok, {:failed, [%{message: "gone"}]}}, _} =
             StorecoveNetwork.status(@connection, "sub-1")

    # A read is safe to repeat: a timeout is transient, not uncertain.
    stub(&Req.Test.transport_error(&1, :timeout))
    assert {{:error, {:transient, _}}, _} = StorecoveNetwork.status(@connection, "sub-1")
  end

  test "routing schemes" do
    assert StorecoveNetwork.routing_scheme("0208") == "BE:EN"
    assert StorecoveNetwork.routing_scheme("9925") == "BE:VAT"
    assert StorecoveNetwork.routing_scheme("9999") == "9999"
  end
end
