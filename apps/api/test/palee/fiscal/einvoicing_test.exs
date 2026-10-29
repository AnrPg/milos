defmodule Palee.Fiscal.EInvoicingTest do
  @moduledoc """
  ADR-250 end to end: issuing a Belgian B2B invoice queues its Peppol
  submission; workers defer without a connection, send through the sandbox
  or Storecove (stubbed), poll the delivery, journal it, keep the attempt
  log, never resend an uncertain submission by themselves, and treat
  webhooks as hints. Runs with Row Level Security enforced.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0]

  alias Palee.{Fiscal, Repo}
  alias Palee.Fiscal.{EInvoiceAttempt, EInvoicing, NetworkConnection}

  @now ~U[2027-02-08 10:00:00.000000Z]

  @identity %{
    legal_name: "Box Bruxelles SRL",
    country_code: "BE",
    tax_id: "0403170701",
    vat_number: "BE0403170701",
    street: "Rue de la Loi",
    building_number: "16",
    postal_code: "1000",
    city: "Bruxelles"
  }

  @buyer %{
    name: "Entreprise Cliente SA",
    vat_number: "BE0202239951",
    street: "Avenue Louise",
    building_number: "54",
    postal_code: "1050",
    city: "Ixelles",
    country_code: "BE"
  }

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)
    {:ok, %{complete: true}} = Fiscal.save_identity(context, @identity, owner.id, @now)

    previous = Application.get_env(:palee, :storecove)
    Application.put_env(:palee, :storecove, base_url: "https://storecove.test/api/v2")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:palee, :storecove, previous),
        else: Application.delete_env(:palee, :storecove)
    end)

    %{organization: organization, owner: owner, context: context}
  end

  defp issue(context, owner, key, extra \\ %{}) do
    {:ok, document, :issued} =
      Fiscal.issue(
        context,
        Map.merge(
          %{
            kind: "invoice",
            issue_date: ~D[2027-02-08],
            idempotency_key: key,
            payment_method: "bank_transfer",
            buyer: @buyer,
            lines: [
              %{description: "Abonnement entreprise", quantity: 10, unit_price_cents: 4_900}
            ]
          },
          extra
        ),
        owner.id,
        @now
      )

    document
  end

  defp submission(context, document),
    do: context |> EInvoicing.submissions_for([document.id]) |> Map.get(document.id)

  defp connect(context, owner, environment, extra \\ %{}) do
    {:ok, connection} =
      EInvoicing.save_connection(
        context,
        Map.merge(%{environment: environment}, extra),
        owner.id,
        @now
      )

    connection
  end

  defp storecove(context, owner) do
    connect(context, owner, "test", %{legal_entity_id: "12345", api_key: "sc-secret-key"})
  end

  defp later(minutes), do: DateTime.add(@now, minutes * 60, :second)

  test "only B2B invoices with a Peppol address are queued", %{context: context, owner: owner} do
    invoice = issue(context, owner, "k-1")

    assert %{status: "pending", recipient_scheme: "0208", recipient_identifier: "0202239951"} =
             submission(context, invoice)

    receipt =
      issue(context, owner, "k-2", %{kind: "receipt", buyer: nil, payment_method: "cash"})

    consumer =
      issue(context, owner, "k-3", %{
        buyer: %{
          name: "Jean Dupont",
          street: "Rue 1",
          postal_code: "1000",
          city: "Bruxelles",
          country_code: "BE"
        }
      })

    own_id =
      issue(context, owner, "k-4", %{
        buyer: Map.merge(@buyer, %{vat_number: nil, peppol_id: "0088:5790000435968"})
      })

    assert submission(context, receipt) == nil
    assert submission(context, consumer) == nil

    assert %{recipient_scheme: "0088", recipient_identifier: "5790000435968"} =
             submission(context, own_id)
  end

  test "without a connection a submission waits without spending attempts", %{
    context: context,
    owner: owner
  } do
    invoice = issue(context, owner, "k-1")
    assert {:ok, %{deferred: 1}} = EInvoicing.transmit(context, :due, @now)

    assert %{status: "pending", attempts: 0, last_error_code: "connection_missing"} =
             submission(context, invoice)
  end

  test "the sandbox submits, delivery is polled and journaled", %{context: context, owner: owner} do
    invoice = issue(context, owner, "k-1")
    connection = connect(context, owner, "sandbox")

    assert connection.peppol_id == "0208:0403170701"
    assert connection.provider == "sandbox"
    assert is_binary(connection.webhook_token)

    assert {:ok, %{submitted: 1}} = EInvoicing.transmit(context, :due, @now)

    assert %{status: "submitted", provider_submission_id: "sandbox-" <> _} =
             submission(context, invoice)

    # Not due before the first poll.
    assert {:ok, %{polling: 0, delivered: 0}} = EInvoicing.transmit(context, :due, @now)
    assert {:ok, %{delivered: 1}} = EInvoicing.transmit(context, :due, later(3))

    assert %{status: "delivered", delivered_at: %DateTime{}} = submission(context, invoice)

    entries = Fiscal.FiscalStore.list_journal_entries(context, %{after_position: 0, limit: 100})
    assert Enum.any?(entries, &(&1.event_type == "document_delivered"))
    assert Enum.any?(entries, &(&1.event_type == "network_connection_saved"))
    assert {:ok, %{valid: true}} = Fiscal.verify_journal(context, owner.id, later(4))
  end

  test "an unreachable receiver is a delivery failure staff can retry with a new GUID", %{
    context: context,
    owner: owner
  } do
    invoice =
      issue(context, owner, "k-1", %{buyer: Map.put(@buyer, :vat_number, "BE0000000097")})

    connect(context, owner, "sandbox")
    first = submission(context, invoice)

    {:ok, _} = EInvoicing.transmit(context, :due, @now)
    {:ok, %{rejected: 1}} = EInvoicing.transmit(context, :due, later(3))

    assert %{status: "rejected", last_error_code: "delivery_failed"} =
             submission(context, invoice)

    assert {:ok, %{status: "pending", attempts: 0}} =
             EInvoicing.retry(context, invoice.id, later(5))

    retried = submission(context, invoice)
    refute retried.idempotency_guid == first.idempotency_guid
    assert retried.provider_submission_id == nil
  end

  test "Storecove gets the UBL, its GUID and routing; the key is never logged", %{
    context: context,
    owner: owner
  } do
    invoice = issue(context, owner, "k-1")
    storecove(context, owner)
    test_pid = self()

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:request, conn.method, conn.request_path,
         Plug.Conn.get_req_header(conn, "authorization"), body}
      )

      case conn.request_path do
        "/api/v2/document_submissions" ->
          Req.Test.json(conn |> Plug.Conn.put_status(200), %{"guid" => "sc-guid-1"})

        "/api/v2/document_submissions/sc-guid-1/evidence/sending" ->
          Req.Test.json(conn, %{"receiving_accesspoint" => "CN=PBE000001", "documents" => []})
      end
    end)

    assert {:ok, %{submitted: 1}} = EInvoicing.transmit(context, :due, @now)

    assert_received {:request, "POST", "/api/v2/document_submissions", ["Bearer sc-secret-key"],
                     body}

    payload = Jason.decode!(body)
    row = submission(context, invoice)
    assert payload["legalEntityId"] == 12_345
    assert payload["idempotencyGuid"] == row.idempotency_guid
    assert payload["routing"]["eIdentifiers"] == [%{"scheme" => "BE:EN", "id" => "0202239951"}]
    assert payload["document"]["rawDocumentData"]["parseStrategy"] == "ubl"

    ubl = Base.decode64!(payload["document"]["rawDocumentData"]["document"])
    assert Palee.PeppolBisRules.check(ubl) == []
    assert ubl =~ invoice.number

    assert {:ok, %{delivered: 1}} = EInvoicing.transmit(context, :due, later(3))

    attempts = bypass_rls(fn -> Repo.all(EInvoiceAttempt) end)
    assert Enum.map(attempts, & &1.operation) |> Enum.sort() == ["status", "submit"]
    refute Enum.any?(attempts, &((&1.request_body || "") =~ "sc-secret-key"))
    refute Enum.any?(attempts, &((&1.response_body || "") =~ "sc-secret-key"))

    # The key is encrypted at rest and never shown.
    [stored] =
      bypass_rls(fn -> Repo.all(from c in "fiscal_network_connections", select: c.api_key) end)

    refute stored =~ "sc-secret-key"
    refute Map.has_key?(EInvoicing.connection(context), :api_key)
  end

  test "an uncertain submission is never sent again by itself", %{context: context, owner: owner} do
    invoice = issue(context, owner, "k-1")
    storecove(context, owner)

    Req.Test.stub(Palee.FiscalHttp, fn conn -> Req.Test.transport_error(conn, :timeout) end)

    assert {:ok, %{uncertain: 1}} = EInvoicing.transmit(context, :due, @now)
    assert %{status: "uncertain", next_attempt_at: nil} = submission(context, invoice)

    Req.Test.stub(Palee.FiscalHttp, fn _conn -> flunk("an uncertain submission was resent") end)
    assert {:ok, %{submitted: 0}} = EInvoicing.transmit(context, :due, later(60 * 24))

    # Staff retry keeps the GUID, so Storecove refuses a copy instead of delivering it twice.
    guid = submission(context, invoice).idempotency_guid
    assert {:ok, _} = EInvoicing.retry(context, invoice.id, later(10))

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      conn
      |> Plug.Conn.put_status(422)
      |> Req.Test.json(%{
        "errors" => [%{"source" => "idempotencyGuid", "details" => "already used"}]
      })
    end)

    assert {:ok, %{uncertain: 1}} = EInvoicing.transmit(context, :due, later(11))
    assert %{status: "uncertain", idempotency_guid: ^guid} = submission(context, invoice)
  end

  test "rejections stop, transient errors back off, refused keys invalidate the connection", %{
    context: context,
    owner: owner
  } do
    invoice = issue(context, owner, "k-1")
    storecove(context, owner)

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
    end)

    assert {:ok, %{retrying: 1}} = EInvoicing.transmit(context, :due, @now)

    assert %{status: "pending", attempts: 1, last_error_code: "transient"} =
             row = submission(context, invoice)

    assert DateTime.compare(row.next_attempt_at, later(1)) == :eq

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{})
    end)

    assert {:ok, %{retrying: 1}} = EInvoicing.transmit(context, :due, later(1))
    assert %{status: "invalid"} = EInvoicing.connection(context)

    assert %{status: "pending", last_error_code: "connection_invalid"} =
             submission(context, invoice)

    storecove(context, owner)

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      conn
      |> Plug.Conn.put_status(422)
      |> Req.Test.json(%{"errors" => [%{"source" => "routing", "details" => "Unknown receiver"}]})
    end)

    assert {:ok, %{rejected: 1}} = EInvoicing.transmit(context, :due, later(2))

    assert %{
             status: "rejected",
             last_error_code: "routing",
             last_error_message: "routing: Unknown receiver"
           } =
             submission(context, invoice)

    assert {:error, :not_found} = EInvoicing.retry(context, Ecto.UUID.generate(), later(3))
  end

  test "a webhook with the right token makes the poll due; a wrong token is not found", %{
    context: context,
    owner: owner
  } do
    invoice = issue(context, owner, "k-1")
    %{webhook_token: token} = connect(context, owner, "sandbox")
    {:ok, %{submitted: 1}} = EInvoicing.transmit(context, :due, @now)
    %{provider_submission_id: id} = submission(context, invoice)

    assert {:error, :not_found} = EInvoicing.webhook(context, "wrong", %{"guid" => id}, @now)

    body = %{
      "guid" => "webhook-guid",
      "body" => Jason.encode!(%{"guid" => id, "event" => "succeeded"})
    }

    assert :ok = EInvoicing.webhook(context, token, body, later(1))
    assert DateTime.compare(submission(context, invoice).next_attempt_at, later(1)) == :eq

    [hash] =
      bypass_rls(fn -> Repo.all(from c in NetworkConnection, select: c.webhook_token_hash) end)

    refute hash == token
  end

  test "connections are validated", %{context: context, owner: owner} do
    assert {:error, {:invalid_fields, errors}} =
             EInvoicing.save_connection(context, %{environment: "production"}, owner.id, @now)

    assert Map.keys(errors) |> Enum.sort() == [:api_key, :legal_entity_id]

    assert {:error, {:invalid_fields, %{peppol_id: ["invalid"]}}} =
             EInvoicing.save_connection(
               context,
               %{environment: "sandbox", peppol_id: "0208:1234"},
               owner.id,
               @now
             )
  end
end
