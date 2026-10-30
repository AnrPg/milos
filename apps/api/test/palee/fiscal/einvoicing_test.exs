defmodule Palee.Fiscal.EInvoicingTest do
  @moduledoc """
  ADR-250 end to end: issuing a Belgian B2B invoice queues its Peppol
  submission; workers defer without a connection, send through the sandbox
  or fiskaly E-INVOICE (stubbed), poll the delivery, journal it, keep the attempt
  log, never resend an uncertain submission by themselves, and treat
  webhooks as hints. Runs with Row Level Security enforced.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0]

  alias Palee.{Fiscal, Repo}
  alias Palee.Fiscal.{EInvoiceAttempt, EInvoicing, NetworkConnection, TillSignatureStore}
  alias Palee.Infrastructure.Fiscal.FiskalyUnified

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

  defp fiskaly(context, owner) do
    connect(context, owner, "test", %{
      legal_entity_id: "0190f8a2-0000-7000-8000-00000000e1e1",
      api_key: "fk-secret-key",
      api_secret: "fk-secret-value"
    })
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

  defp stub_fiskaly(transaction, records \\ %{}) do
    test_pid = self()

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:request, conn.method, conn.request_path,
         Plug.Conn.get_req_header(conn, "x-idempotency-key"), body}
      )

      reply = fn status, json -> conn |> Plug.Conn.put_status(status) |> Req.Test.json(json) end

      case {conn.method, conn.request_path} do
        {"POST", "/tokens"} ->
          reply.(200, %{"content" => %{"authentication" => %{"bearer" => "jwt"}}})

        {"GET", "/systems/" <> _id} ->
          reply.(200, %{
            "content" => %{
              "vat_rates" => [%{"code" => "STANDARD", "percentage" => "21.00"}],
              "vat_exemptions" => []
            }
          })

        {"POST", "/records"} ->
          case Jason.decode!(body) do
            %{"content" => %{"type" => "INTENTION"}} ->
              reply.(200, %{"content" => %{"id" => "rec-intention", "state" => "COMPLETED"}})

            _transaction ->
              case transaction.() do
                {status, json} -> reply.(status, json)
                :timeout -> Req.Test.transport_error(conn, :timeout)
              end
          end

        {"GET", "/records/" <> id} ->
          reply.(200, %{"content" => Map.fetch!(records, id)})
      end
    end)
  end

  defp accepted, do: {200, %{"content" => %{"id" => "rec-tx", "state" => "ACCEPTED"}}}

  test "fiskaly gets the invoice's fields with derived keys; credentials are never logged", %{
    context: context,
    owner: owner
  } do
    invoice = issue(context, owner, "k-1")
    connection = fiskaly(context, owner)
    assert %{provider: "fiskaly", credentials_source: "own", has_api_secret: true} = connection

    stub_fiskaly(&accepted/0, %{
      "rec-tx" => %{"id" => "rec-tx", "state" => "COMPLETED", "used_in" => %{"id" => "rec-tm"}},
      "rec-tm" => %{"id" => "rec-tm", "state" => "COMPLETED", "mode" => "FINISHED"}
    })

    assert {:ok, %{submitted: 1}} = EInvoicing.transmit(context, :due, @now)
    row = submission(context, invoice)
    assert %{status: "submitted", provider_submission_id: "rec-tx"} = row

    transaction_key =
      FiskalyUnified.idempotency_key("einvoice:#{row.idempotency_guid}:transaction")

    assert_received {:request, "POST", "/records", [^transaction_key], body}
    operation = Jason.decode!(body)["content"]["operation"]
    assert operation["type"] == "INVOICE"
    assert operation["document"]["number"] == invoice.number

    assert [%{"invoicing" => %{"type" => "PEPPOL", "identifier" => "0208:0202239951"}}] =
             operation["recipients"]

    assert {:ok, %{delivered: 1}} = EInvoicing.transmit(context, :due, later(3))
    assert %{status: "delivered"} = submission(context, invoice)

    attempts = bypass_rls(fn -> Repo.all(EInvoiceAttempt) end)
    assert Enum.map(attempts, & &1.operation) |> Enum.sort() == ["status", "submit"]

    for attempt <- attempts, text <- ["fk-secret-key", "fk-secret-value"] do
      refute (attempt.request_body || "") =~ text
      refute (attempt.response_body || "") =~ text
    end

    # Key and secret are encrypted at rest and never shown.
    [{stored_key, stored_secret}] =
      bypass_rls(fn ->
        Repo.all(from c in "fiscal_network_connections", select: {c.api_key, c.api_secret})
      end)

    refute stored_key =~ "fk-secret-key"
    refute stored_secret =~ "fk-secret-value"
    shown = EInvoicing.connection(context)
    refute Map.has_key?(shown, :api_key)
    refute Map.has_key?(shown, :api_secret)
  end

  test "without its own credentials a fiskaly connection uses the fiskaly till connection's", %{
    context: context,
    owner: owner
  } do
    assert {:error, {:invalid_fields, errors}} =
             EInvoicing.save_connection(
               context,
               %{environment: "test", legal_entity_id: "sys-1"},
               owner.id,
               @now
             )

    assert Map.keys(errors) |> Enum.sort() == [:api_key, :api_secret]

    {:ok, _till} =
      TillSignatureStore.save_connection(context, "tse", %{
        provider: "fiskaly",
        environment: "test",
        api_key: "till-key",
        api_secret: "till-secret",
        unit_id: Ecto.UUID.generate(),
        register_id: Ecto.UUID.generate(),
        status: "active",
        provisioned_at: @now
      })

    connection = connect(context, owner, "test", %{legal_entity_id: "sys-1"})
    assert %{credentials_source: "till_connection", has_api_key: false} = connection

    invoice = issue(context, owner, "k-1")
    test_pid = self()

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      if conn.request_path == "/tokens", do: send(test_pid, {:token, Jason.decode!(body)})

      case {conn.method, conn.request_path} do
        {"POST", "/tokens"} ->
          Req.Test.json(conn, %{"content" => %{"authentication" => %{"bearer" => "jwt"}}})

        {"GET", _path} ->
          Req.Test.json(conn, %{
            "content" => %{"vat_rates" => [%{"code" => "STANDARD", "percentage" => "21.00"}]}
          })

        {"POST", "/records"} ->
          Req.Test.json(conn, %{"content" => %{"id" => "rec-1", "state" => "ACCEPTED"}})
      end
    end)

    assert {:ok, %{submitted: 1}} = EInvoicing.transmit(context, :due, @now)
    assert_received {:token, %{"content" => %{"key" => "till-key", "secret" => "till-secret"}}}
    assert %{status: "submitted"} = submission(context, invoice)
  end

  test "an uncertain submission is never sent again by itself", %{context: context, owner: owner} do
    invoice = issue(context, owner, "k-1")
    fiskaly(context, owner)

    stub_fiskaly(fn -> :timeout end)

    assert {:ok, %{uncertain: 1}} = EInvoicing.transmit(context, :due, @now)
    assert %{status: "uncertain", next_attempt_at: nil} = submission(context, invoice)

    Req.Test.stub(Palee.FiscalHttp, fn _conn -> flunk("an uncertain submission was resent") end)
    assert {:ok, %{submitted: 0}} = EInvoicing.transmit(context, :due, later(60 * 24))

    # Staff retry keeps the GUID, so fiskaly replays (or refuses) instead of
    # creating a second invoice.
    guid = submission(context, invoice).idempotency_guid
    assert {:ok, _} = EInvoicing.retry(context, invoice.id, later(10))

    stub_fiskaly(fn ->
      {422, %{"code" => "E_IDEMPOTENCY", "message" => "Idempotency key reused"}}
    end)

    assert {:ok, %{uncertain: 1}} = EInvoicing.transmit(context, :due, later(11))
    assert %{status: "uncertain", idempotency_guid: ^guid} = submission(context, invoice)

    key = FiskalyUnified.idempotency_key("einvoice:#{guid}:transaction")
    assert_received {:request, "POST", "/records", [^key], _body}
  end

  test "rejections stop, transient errors back off, refused keys invalidate the connection", %{
    context: context,
    owner: owner
  } do
    invoice = issue(context, owner, "k-1")
    fiskaly(context, owner)

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
    end)

    assert {:ok, %{retrying: 1}} = EInvoicing.transmit(context, :due, @now)

    assert %{status: "pending", attempts: 1, last_error_code: "transient"} =
             row = submission(context, invoice)

    assert DateTime.compare(row.next_attempt_at, later(1)) == :eq

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"code" => "E_UNAUTHORIZED"})
    end)

    assert {:ok, %{retrying: 1}} = EInvoicing.transmit(context, :due, later(1))
    assert %{status: "invalid"} = EInvoicing.connection(context)

    assert %{status: "pending", last_error_code: "connection_invalid"} =
             submission(context, invoice)

    fiskaly(context, owner)

    stub_fiskaly(fn ->
      {422, %{"code" => "E_VALIDATION", "message" => "Unknown receiver"}}
    end)

    assert {:ok, %{rejected: 1}} = EInvoicing.transmit(context, :due, later(2))

    assert %{
             status: "rejected",
             last_error_code: "E_VALIDATION",
             last_error_message: "E_VALIDATION: Unknown receiver"
           } = submission(context, invoice)

    assert {:error, :not_found} = EInvoicing.retry(context, Ecto.UUID.generate(), later(3))
  end

  test "an old Storecove connection is invalid until reconnected through fiskaly", %{
    context: context,
    organization: organization,
    owner: owner
  } do
    invoice = issue(context, owner, "k-1")

    bypass_rls(fn ->
      Repo.insert!(%NetworkConnection{
        organization_id: organization.id,
        network: "peppol",
        provider: "storecove",
        environment: "test",
        peppol_scheme: "0208",
        peppol_identifier: "0403170701",
        legal_entity_id: "123",
        api_key: "old-key",
        status: "active"
      })
    end)

    Req.Test.stub(Palee.FiscalHttp, fn _conn -> flunk("no request expected") end)

    assert {:ok, %{deferred: 1}} = EInvoicing.transmit(context, :due, @now)
    assert %{status: "invalid", provider: "storecove"} = EInvoicing.connection(context)

    assert %{status: "pending", last_error_code: "connection_invalid"} =
             submission(context, invoice)

    # Reconnecting through fiskaly drops Storecove's key.
    assert %{provider: "fiskaly", status: "active", credentials_source: "own"} =
             fiskaly(context, owner)

    [stored] = bypass_rls(fn -> Repo.all(NetworkConnection) end)
    assert stored.api_key == "fk-secret-key"

    assert {:error, {:invalid_fields, %{provider: ["invalid"]}}} =
             EInvoicing.save_connection(
               context,
               %{environment: "test", provider: "storecove", legal_entity_id: "1", api_key: "k"},
               owner.id,
               @now
             )
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

    assert Map.keys(errors) |> Enum.sort() == [:api_key, :api_secret, :legal_entity_id]

    assert {:error, {:invalid_fields, %{peppol_id: ["invalid"]}}} =
             EInvoicing.save_connection(
               context,
               %{environment: "sandbox", peppol_id: "0208:1234"},
               owner.id,
               @now
             )
  end
end
