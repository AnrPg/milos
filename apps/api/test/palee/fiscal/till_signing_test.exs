defmodule Palee.Fiscal.TillSigningTest do
  @moduledoc """
  ADR-251 end to end: receipts issued in Germany and Austria queue their
  TSE/RKSV signature; workers defer without a connection, provision and
  sign through the sandbox or fiskaly (stubbed), read uncertain
  transactions back instead of signing them twice, record a German TSE
  failure after the outage window and an Austrian unit outage, and journal
  every signature. Runs with Row Level Security enforced.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0]

  alias Palee.{Fiscal, Repo}
  alias Palee.Fiscal.{TillConnection, TillSignatureAttempt, TillSigning}
  alias Palee.Fiscal.Domain.RksvReceipt

  @now ~U[2027-02-08 10:00:00.000000Z]

  @germany %{
    legal_name: "Box Berlin GmbH",
    country_code: "DE",
    tax_id: "2181508150",
    street: "Torstraße",
    building_number: "1",
    postal_code: "10119",
    city: "Berlin"
  }

  @austria %{
    legal_name: "Box Wien GmbH",
    country_code: "AT",
    tax_id: "123456789",
    street: "Ringstraße",
    building_number: "1",
    postal_code: "1010",
    city: "Wien"
  }

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)

    for {key, url} <- [
          fiskaly_sign_de: "https://fiskaly-de.test/api/v2",
          fiskaly_sign_at: "https://fiskaly-at.test/api/v1"
        ] do
      previous = Application.get_env(:palee, key)
      Application.put_env(:palee, key, base_url: url)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:palee, key, previous),
          else: Application.delete_env(:palee, key)
      end)
    end

    %{organization: organization, owner: owner, context: context}
  end

  defp identity(context, owner, identity) do
    {:ok, %{complete: true}} = Fiscal.save_identity(context, identity, owner.id, @now)
  end

  defp issue(context, owner, key, extra \\ %{}, at \\ @now) do
    {:ok, document, :issued} =
      Fiscal.issue(
        context,
        Map.merge(
          %{
            kind: "receipt",
            issue_date: ~D[2027-02-08],
            idempotency_key: key,
            payment_method: "cash",
            lines: [
              %{description: "Monatsbeitrag", quantity: 1, unit_price_cents: 5_950},
              %{
                description: "Wasser",
                quantity: 2,
                unit_price_cents: 150,
                tax_category: "reduced"
              }
            ]
          },
          extra
        ),
        owner.id,
        at
      )

    document
  end

  defp signature(context, document),
    do: context |> TillSigning.signatures_for([document.id]) |> Map.get(document.id)

  defp later(seconds), do: DateTime.add(@now, seconds, :second)

  defp connect(context, owner, device, environment, extra \\ %{}) do
    TillSigning.save_connection(
      context,
      device,
      Map.merge(%{environment: environment}, extra),
      owner.id,
      @now
    )
  end

  defp journal(context),
    do: Fiscal.FiscalStore.list_journal_entries(context, %{after_position: 0, limit: 200})

  # ── Germany ─────────────────────────────────────────────────────────────

  describe "Germany (TSE)" do
    setup %{context: context, owner: owner} do
      identity(context, owner, @germany)
      :ok
    end

    test "receipts and their credit notes are queued, invoices are not", %{
      context: context,
      owner: owner
    } do
      receipt = issue(context, owner, "k-1")
      assert %{device: "tse", kind: "receipt", status: "pending"} = signature(context, receipt)

      invoice =
        issue(context, owner, "k-2", %{
          kind: "invoice",
          payment_method: "bank_transfer",
          buyer: %{
            name: "Firma",
            street: "Weg 1",
            postal_code: "10115",
            city: "Berlin",
            country_code: "DE"
          }
        })

      assert signature(context, invoice) == nil

      {:ok, credit, :issued} =
        Fiscal.credit(context, receipt.id, :all, ~D[2027-02-08], "credit-1", owner.id, @now)

      assert %{device: "tse"} = signature(context, credit)

      assert {:ok, %{deferred: 2}} = TillSigning.transmit(context, :due, @now)

      assert %{status: "pending", attempts: 0, last_error_code: "connection_missing"} =
               signature(context, receipt)
    end

    test "the sandbox provisions, signs, prints and journals", %{context: context, owner: owner} do
      receipt = issue(context, owner, "k-1")
      assert {:ok, connection} = connect(context, owner, "tse", "sandbox")
      assert %{status: "active", provider: "sandbox", unit_serial: "SANDBOX-" <> _} = connection

      assert {:ok, %{signed: 1}} = TillSigning.transmit(context, :due, later(5))

      signed = signature(context, receipt)
      assert %{status: "signed", transaction_number: n, signature_counter: c} = signed
      assert is_integer(n) and is_integer(c)
      labels = signed |> TillSigning.print() |> Enum.map(& &1.label)

      assert "Transaktionsnummer" in labels and "Signaturzähler" in labels and
               "Signatur" in labels

      events = context |> journal() |> Enum.map(& &1.event_type)
      assert "till_connection_saved" in events and "receipt_signed" in events
      assert {:ok, %{valid: true}} = Fiscal.verify_journal(context, owner.id, later(10))
    end

    test "fiskaly SIGN DE: TSS and client set-up, then start and finish with cloud data", %{
      context: context,
      owner: owner
    } do
      test_pid = self()

      Req.Test.stub(Palee.FiscalHttp, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:fiskaly, conn.method, conn.request_path, conn.query_string, body})
        fiskaly_de(conn, body)
      end)

      receipt = issue(context, owner, "k-1")

      assert {:ok,
              %{status: "active", unit_serial: "tss-serial", register_serial: "client-serial"}} =
               connect(context, owner, "tse", "test", %{
                 api_key: "fk-key",
                 api_secret: "fk-secret"
               })

      calls = drain()

      assert Enum.map(calls, fn {method, path, _query, _body} -> {method, strip(path)} end) == [
               {"POST", "/auth"},
               {"PUT", "/tss"},
               {"PATCH", "/tss"},
               {"PATCH", "/tss/admin"},
               {"POST", "/tss/admin/auth"},
               {"PATCH", "/tss"},
               {"PUT", "/tss/client"},
               {"POST", "/tss/admin/logout"}
             ]

      assert {:ok, %{signed: 1}} = TillSigning.transmit(context, :due, later(5))

      [{"POST", _, _, _}, {"PUT", _, "tx_revision=1", _}, {"PUT", _, "tx_revision=2", finish}] =
        drain()

      receipt_data = Jason.decode!(finish)["schema"]["standard_v1"]["receipt"]
      assert receipt_data["receipt_type"] == "RECEIPT"

      assert receipt_data["amounts_per_vat_rate"] == [
               %{"vat_rate" => "NORMAL", "amount" => "59.50"},
               %{"vat_rate" => "REDUCED_1", "amount" => "3.00"}
             ]

      assert receipt_data["amounts_per_payment_type"] == [
               %{"payment_type" => "CASH", "amount" => "62.50", "currency_code" => "EUR"}
             ]

      assert %{
               status: "signed",
               transaction_number: 18,
               signature_counter: 112,
               signature_value: "MEQCIAy4",
               signature_algorithm: "ecdsa-plain-SHA256",
               time_format: "unixTime",
               unit_serial: "tss-serial",
               register_serial: "client-serial",
               started_at_device: ~U[2027-02-08 10:00:01.000000Z],
               finished_at_device: ~U[2027-02-08 10:00:02.000000Z],
               qr_code_data: "V0;client-serial;Kassenbeleg-V1;" <> _
             } = signature(context, receipt)

      # Credentials are encrypted at rest and never logged.
      attempts = bypass_rls(fn -> Repo.all(TillSignatureAttempt) end)
      refute Enum.any?(attempts, &((&1.request_body || "") =~ "fk-secret"))

      [{key, secret, pin}] =
        bypass_rls(fn ->
          Repo.all(
            from c in "fiscal_till_connections", select: {c.api_key, c.api_secret, c.admin_pin}
          )
        end)

      refute key =~ "fk-key"
      refute secret =~ "fk-secret"
      assert is_binary(pin)
      [stored] = bypass_rls(fn -> Repo.all(TillConnection) end)
      assert is_binary(stored.admin_pin) and byte_size(stored.admin_pin) >= 6
      refute Map.has_key?(TillSigning.connection(context, "tse"), :admin_pin)
    end

    test "an uncertain finish is read back, never signed twice", %{context: context, owner: owner} do
      Req.Test.stub(Palee.FiscalHttp, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        fiskaly_de(conn, body)
      end)

      {:ok, _} =
        connect(context, owner, "tse", "test", %{api_key: "fk-key", api_secret: "fk-secret"})

      receipt = issue(context, owner, "k-1")

      Req.Test.stub(Palee.FiscalHttp, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        if conn.query_string == "tx_revision=2",
          do: Req.Test.transport_error(conn, :timeout),
          else: fiskaly_de(conn, body)
      end)

      assert {:ok, %{uncertain: 1}} = TillSigning.transmit(context, :due, later(5))
      assert %{status: "uncertain"} = signature(context, receipt)

      test_pid = self()

      Req.Test.stub(Palee.FiscalHttp, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:fiskaly, conn.method, conn.request_path, conn.query_string, body})
        if conn.method == "PUT", do: flunk("an uncertain transaction was signed again")
        fiskaly_de(conn, body)
      end)

      assert {:ok, %{signed: 1}} = TillSigning.transmit(context, :due, later(40))
      assert [{"POST", _, _, _}, {"GET", "/api/v2/tss/" <> _, "", ""}] = drain()
      assert %{status: "signed", transaction_number: 18} = signature(context, receipt)
    end

    test "a receipt the TSE cannot sign in time is recorded as a TSE failure", %{
      context: context,
      owner: owner
    } do
      Req.Test.stub(Palee.FiscalHttp, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        fiskaly_de(conn, body)
      end)

      {:ok, _} =
        connect(context, owner, "tse", "test", %{api_key: "fk-key", api_secret: "fk-secret"})

      receipt = issue(context, owner, "k-1")

      Req.Test.stub(Palee.FiscalHttp, fn conn ->
        if conn.request_path == "/api/v2/auth",
          do: Req.Test.json(conn, %{"access_token" => "token"}),
          else: conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{"code" => "E_TSS_LOCKED"})
      end)

      assert {:ok, %{retrying: 1}} = TillSigning.transmit(context, :due, later(5))
      assert %{status: "pending", last_error_code: "transient"} = signature(context, receipt)

      assert {:ok, %{device_failed: 1}} = TillSigning.transmit(context, :due, later(400))

      failed = signature(context, receipt)
      assert %{status: "device_failed", failed_at: %DateTime{}} = failed
      assert [%{label: "TSE", value: "TSE ausgefallen"} | _] = TillSigning.print(failed)
      assert "till_device_failed" in (context |> journal() |> Enum.map(& &1.event_type))
      assert {:error, :not_retryable} = TillSigning.retry(context, failed.id, later(500))
    end

    test "a connection is only for the business's country", %{context: context, owner: owner} do
      assert {:error, {:invalid_fields, %{device: ["not_for_country"]}}} =
               connect(context, owner, "rksv", "sandbox")

      assert {:error, {:invalid_fields, errors}} = connect(context, owner, "tse", "production")
      assert Map.keys(errors) |> Enum.sort() == [:api_key, :api_secret]

      Req.Test.stub(Palee.FiscalHttp, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{})
      end)

      assert {:error, :till_credentials_refused} =
               connect(context, owner, "tse", "test", %{api_key: "bad", api_secret: "bad"})

      assert %{status: "provisioning", last_error: error} = TillSigning.connection(context, "tse")
      assert is_binary(error)
    end
  end

  # ── Austria ─────────────────────────────────────────────────────────────

  describe "Austria (RKSV)" do
    setup %{context: context, owner: owner} do
      identity(context, owner, @austria)
      :ok
    end

    test "the sandbox signs the start receipt, receipts and null receipts", %{
      context: context,
      owner: owner
    } do
      receipt =
        issue(context, owner, "k-1", %{
          lines: [%{description: "Monatsbeitrag", quantity: 1, unit_price_cents: 6_000}]
        })

      assert {:error, :till_not_connected} = TillSigning.null_receipt(context, @now)

      assert {:ok, %{status: "active"}} = connect(context, owner, "rksv", "sandbox")

      assert [%{kind: "start", status: "signed", document_id: nil}] =
               context
               |> TillSigning.list(%{})
               |> Map.fetch!(:signatures)
               |> Enum.reject(&(&1.kind == "receipt"))

      assert {:ok, %{signed: 1}} = TillSigning.transmit(context, :due, later(5))
      signed = signature(context, receipt)
      assert {:ok, parsed} = RksvReceipt.parse_code(signed.qr_code_data)
      assert parsed.amounts["STANDARD"] == "60,00"
      refute parsed.device_failed
      refute Enum.any?(TillSigning.print(signed), &(&1.value == RksvReceipt.failed_marker()))

      assert {:ok, null} = TillSigning.null_receipt(context, later(10))
      assert {:ok, %{signed: 1}} = TillSigning.transmit(context, :due, later(10))

      assert %{kind: "null", status: "signed", document_id: nil} =
               TillSigning.get(context, null.id)
    end

    test "fiskaly SIGN AT: a unit outage is printed as 'Sicherheitseinrichtung ausgefallen'", %{
      context: context,
      owner: owner
    } do
      test_pid = self()

      Req.Test.stub(Palee.FiscalHttp, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:fiskaly, conn.method, conn.request_path, conn.query_string, body})
        fiskaly_at(conn, body)
      end)

      assert {:ok, %{status: "active", register_serial: "kasse-1"}} =
               connect(context, owner, "rksv", "test", %{
                 api_key: "fk-key",
                 api_secret: "fk-secret"
               })

      assert Enum.map(drain(), fn {method, path, _q, _b} -> {method, strip(path)} end) == [
               {"POST", "/auth"},
               {"PUT", "/signature-creation-unit"},
               {"PATCH", "/signature-creation-unit"},
               {"PUT", "/cash-register"},
               {"PATCH", "/cash-register"},
               {"PATCH", "/cash-register"},
               {"GET", "/cash-register/receipt/1"}
             ]

      assert %{signatures: [%{kind: "start", status: "signed", receipt_number: "1"}]} =
               TillSigning.list(context, %{})

      receipt = issue(context, owner, "k-1")
      assert {:ok, %{device_failed: 1}} = TillSigning.transmit(context, :due, later(5))

      [{"POST", _, _, _}, {"PUT", "/api/v1/cash-register/" <> _, _, body}] = drain()

      assert Jason.decode!(body)["schema"]["standard_v1"]["receipt"]["amounts_per_vat_rate"] == [
               %{"vat_rate" => "STANDARD", "amount" => "59.50"},
               %{"vat_rate" => "REDUCED_2", "amount" => "3.00"}
             ]

      failed = signature(context, receipt)

      assert %{
               status: "device_failed",
               receipt_number: "2",
               qr_code_data: "_R1-AT1_kasse-1_2_" <> _
             } = failed

      assert Enum.any?(
               TillSigning.print(failed),
               &(&1.value == "Sicherheitseinrichtung ausgefallen")
             )
    end
  end

  # ── fiskaly stubs ───────────────────────────────────────────────────────

  defp drain(acc \\ []) do
    receive do
      {:fiskaly, method, path, query, body} -> drain([{method, path, query, body} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # "/api/v2/tss/<uuid>/client/<uuid>" → "/tss/client"
  defp strip(path) do
    path
    |> String.replace(~r"^/api/v[12]", "")
    |> String.replace(~r"/[0-9a-f]{8}-[0-9a-f-]{27}", "")
  end

  defp fiskaly_de(conn, _body) do
    path = strip(conn.request_path)

    case {conn.method, path} do
      {"POST", "/auth"} ->
        Req.Test.json(conn, %{"access_token" => "token"})

      {"PUT", "/tss"} ->
        Req.Test.json(conn, %{
          "state" => "CREATED",
          "admin_puk" => "puk",
          "serial_number" => "tss-serial",
          "public_key" => "pk"
        })

      {"PATCH", "/tss"} ->
        Req.Test.json(conn, %{
          "state" => "INITIALIZED",
          "serial_number" => "tss-serial",
          "public_key" => "pk"
        })

      {"PUT", "/tss/client"} ->
        Req.Test.json(conn, %{"serial_number" => "client-serial", "state" => "REGISTERED"})

      {"PUT", "/tss/tx"} ->
        state = if conn.query_string == "tx_revision=1", do: "ACTIVE", else: "FINISHED"
        Req.Test.json(conn, tx(state))

      {"GET", "/tss/tx"} ->
        Req.Test.json(conn, tx("FINISHED"))

      {_method, "/tss/admin" <> _} ->
        Req.Test.json(conn, %{})
    end
  end

  defp tx("ACTIVE"), do: %{"state" => "ACTIVE", "number" => 18, "latest_revision" => 1}

  defp tx("FINISHED") do
    %{
      "state" => "FINISHED",
      "number" => 18,
      "time_start" => 1_802_080_801,
      "time_end" => 1_802_080_802,
      "tss_serial_number" => "tss-serial",
      "client_serial_number" => "client-serial",
      "signature" => %{
        "value" => "MEQCIAy4",
        "algorithm" => "ecdsa-plain-SHA256",
        "counter" => 112,
        "public_key" => "pk"
      },
      "log" => %{
        "timestamp_format" => "unixTime",
        "operation" => "FINISH",
        "timestamp" => 1_802_080_802
      },
      "qr_code_data" =>
        "V0;client-serial;Kassenbeleg-V1;Beleg^59.50_3.00_0.00_0.00_0.00^62.50:Bar;18;112;..."
    }
  end

  defp fiskaly_at(conn, _body) do
    case {conn.method, strip(conn.request_path)} do
      {"POST", "/auth"} ->
        Req.Test.json(conn, %{"access_token" => "token"})

      {_method, "/signature-creation-unit"} ->
        Req.Test.json(conn, %{"state" => "INITIALIZED", "certificate_serial_number" => "5c8e5"})

      {_method, "/cash-register"} ->
        Req.Test.json(conn, %{"state" => "INITIALIZED", "serial_number" => "kasse-1"})

      {"GET", "/cash-register/receipt/1"} ->
        Req.Test.json(conn, at_receipt("1", Base.encode64("start-signature"), []))

      {"PUT", "/cash-register/receipt"} ->
        Req.Test.json(
          conn,
          at_receipt("2", RksvReceipt.failed_signature(), ["Sicherheitseinrichtung ausgefallen"])
        )
    end
  end

  defp at_receipt(number, signature, hints) do
    %{
      "receipt_number" => number,
      "time_signature" => 1_802_080_805,
      "cash_register_serial_number" => "kasse-1",
      "signed" => true,
      "hints" => hints,
      "qr_code_data" =>
        "_R1-AT1_kasse-1_#{number}_2027-02-08T11:00:05_59,50_0,00_3,00_0,00_0,00_" <>
          "dGVzdA==_5c8e5_cHJldg==_" <> signature
    }
  end
end
