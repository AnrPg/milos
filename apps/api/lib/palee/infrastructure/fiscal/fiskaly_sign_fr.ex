defmodule Palee.Infrastructure.Fiscal.FiskalySignFr do
  @moduledoc """
  fiskaly SIGN FR (Unified API `2026-06-01`), the French till signing
  service (ADR-266) behind the `CashRegisterSecurity` port, with the
  business's fiskaly account (the same one as E-INVOICE, ADR-250).

    * Provisioning (`provision/2`): `POST /taxpayers` (a `COMPANY` with
      `fiscalization: {type: FR, tax_id_number: <SIREN>, credentials}`)
      → `PATCH {state: COMMISSIONED}` → `POST /locations` (a `BRANCH`,
      `label` = the SIRET) → commission → `POST /systems` (a
      `FISCAL_DEVICE`, producer and software Palee) → commission. The
      taxpayer id is kept as the connection's `unit_serial`, the System id
      as its `register_serial`. The `credentials` (how Palee's software is
      certified: `LNE`, `INFOCERT` or `SELF_ATTESTATION`) come from config
      (`:palee, :fiskaly_sign_fr, credentials:`) and must be confirmed with
      fiskaly before the first French box (ADR-266).
    * Signing (`sign/2`): `INTENTION` then `TRANSACTION::RECEIPT` (a credit
      note: `TRANSACTION::CORRECTION` of the receipt's fiskaly record) on
      the System. The answer's `compliance.sequence` (number, signature)
      and `journal` (signature, `signed_at`) are the signature; the
      TRANSACTION record id is kept as `receipt_number`, which a later
      correction refers to. A receipt sent after an outage carries
      `document.offline`.
    * Read-back (`lookup/2`): the same two requests with the same
      idempotency keys (UUID v3 from Palee's external id), which fiskaly
      answers from its 24-hour idempotency cache, then `GET /records/{id}`
      for the current state. Never a second record within those 24 hours.

  Hosts as in `FiskalyUnified`. Written from fiskaly's public spec
  (https://workspace.fiskaly.com/specs/fiskaly.uapi.sign-fr.2026-06-01.yaml);
  to be confirmed against a fiskaly TEST account before the first live box.
  """

  @behaviour Palee.Fiscal.Ports.CashRegisterSecurity

  alias Palee.Infrastructure.Fiscal.{FiskalyUnified, Http}

  # ── Provisioning ────────────────────────────────────────────────────────

  @impl true
  def provision(connection, context) do
    run(connection, nil, fn token ->
      prefix = "sign_fr:" <> connection.register_id

      with {:ok, siren} <- siren(context),
           {:ok, taxpayer} <-
             create(
               connection,
               token,
               "/taxpayers",
               taxpayer(context, siren),
               prefix <> ":taxpayer"
             ),
           {:ok, _} <-
             commission(connection, token, "/taxpayers/", taxpayer, prefix <> ":taxpayer"),
           {:ok, location} <-
             create(
               connection,
               token,
               "/locations",
               location(context, taxpayer),
               prefix <> ":location"
             ),
           {:ok, _} <-
             commission(connection, token, "/locations/", location, prefix <> ":location"),
           {:ok, system} <-
             create(connection, token, "/systems", system(context, location), prefix <> ":system"),
           {:ok, _} <- commission(connection, token, "/systems/", system, prefix <> ":system") do
        {:ok,
         %{
           unit_serial: taxpayer,
           register_serial: system,
           public_key: nil,
           admin_pin: nil,
           start: nil
         }}
      end
    end)
  end

  defp create(connection, token, path, body, name) do
    case FiskalyUnified.post(
           connection,
           token,
           path,
           %{content: body},
           FiskalyUnified.idempotency_key(name)
         ) do
      {:ok, %{"content" => %{"id" => id}}} when is_binary(id) -> {:ok, id}
      {:ok, _other} -> {:error, {:uncertain, :id_missing}}
      error -> error
    end
  end

  defp commission(connection, token, path, id, name) do
    FiskalyUnified.patch(
      connection,
      token,
      path <> URI.encode_www_form(id),
      %{content: %{state: "COMMISSIONED"}},
      FiskalyUnified.idempotency_key(name <> ":commission")
    )
  end

  # The SIREN is the first nine digits of the SIRET (or the SIREN itself).
  defp siren(context) do
    digits =
      [context[:registration_number], context[:tax_id]]
      |> Enum.find_value("", &(is_binary(&1) && &1 != "" && &1))
      |> String.replace(~r/\D/, "")

    if String.length(digits) in [9, 14],
      do: {:ok, String.slice(digits, 0, 9)},
      else:
        {:error,
         {:rejected,
          [%{code: "siren_missing", message: "A SIREN or SIRET is needed for SIGN FR"}]}}
  end

  defp siret(context) do
    digits = String.replace(context[:registration_number] || "", ~r/\D/, "")
    if String.length(digits) == 14, do: digits
  end

  defp taxpayer(context, siren) do
    credentials =
      :palee
      |> Application.get_env(:fiskaly_sign_fr, [])
      |> Keyword.get(:credentials, %{type: "SELF_ATTESTATION"})

    properties =
      %{
        "vat_number_eu" => context[:vat_number],
        "naf_ape_code" => context[:activity_code],
        "billing_siret" => siret(context)
      }
      |> Map.reject(fn {_key, value} -> value in [nil, ""] end)

    %{
      type: "COMPANY",
      name: %{
        legal: String.slice(context[:legal_name] || "-", 0, 128),
        trade: String.slice(context[:trade_name] || context[:legal_name] || "-", 0, 128)
      },
      address: address(context),
      fiscalization: %{
        type: "FR",
        tax_id_number: siren,
        credentials: Map.put(Map.new(credentials), :properties, properties)
      }
    }
  end

  defp location(context, taxpayer) do
    %{
      type: "BRANCH",
      taxpayer: %{id: taxpayer},
      name: String.slice(context[:trade_name] || context[:legal_name] || "Palee", 0, 128),
      address: address(context)
    }
    |> then(fn body ->
      case siret(context) do
        nil -> body
        siret -> Map.put(body, :label, siret)
      end
    end)
  end

  defp system(context, location) do
    %{
      type: "FISCAL_DEVICE",
      location: %{id: location},
      producer: %{
        type: "MPN",
        number: "PALEE",
        details: %{
          name: "Palee",
          label: String.slice(context[:register_serial] || "Palee", 0, 64)
        }
      },
      software: %{name: "Palee", version: software_version()}
    }
  end

  defp software_version do
    case :application.get_key(:palee, :vsn) do
      {:ok, vsn} -> to_string(vsn)
      _none -> "3.0.0"
    end
  end

  defp address(context) do
    %{
      line: %{
        type: "STREET_NUMBER",
        street: present(context[:street]),
        number: present(context[:building_number])
      },
      code: present(context[:postal_code]),
      city: present(context[:city]),
      country: context[:country_code] || "FR"
    }
  end

  defp present(value) when is_binary(value) and value != "", do: String.slice(value, 0, 128)
  defp present(_value), do: "-"

  # ── Check (ADR-273) ─────────────────────────────────────────────────────

  @doc """
  «Δοκιμή σύνδεσης»: a token for the key, then the System Palee
  provisioned (`GET /systems/{id}`). Nothing is signed.
  """
  @impl true
  def check(connection) do
    {result, _wire} =
      run(connection, nil, fn token ->
        with {:ok, system} <- system_id(connection),
             {:ok, _vat} <- FiskalyUnified.vat_table(connection, token, system) do
          {:ok, %{}}
        end
      end)

    case result do
      {:error, {:rejected, [%{code: code} | _]}}
      when code in ["system_not_found", "not_provisioned", "not_found"] ->
        {:error, :unit_not_found}

      other ->
        other
    end
  end

  # ── Signing ─────────────────────────────────────────────────────────────

  @impl true
  def sign(connection, %{external_id: id, schema: schema}) do
    run(connection, schema, fn token ->
      with {:ok, system} <- system_id(connection),
           {:ok, vat} <- FiskalyUnified.vat_table(connection, token, system),
           {:ok, operation} <- operation(schema, vat),
           {:ok, record} <-
             FiskalyUnified.record(connection, token, system, operation, "sign_fr:" <> id) do
        signature(connection, record)
      end
    end)
  end

  @impl true
  def lookup(connection, %{external_id: id, schema: schema}) do
    run(connection, nil, fn token ->
      with {:ok, system} <- system_id(connection),
           {:ok, vat} <- FiskalyUnified.vat_table(connection, token, system),
           {:ok, operation} <- operation(schema, vat),
           {:ok, %{"id" => record_id}} <-
             FiskalyUnified.record(connection, token, system, operation, "sign_fr:" <> id),
           {:ok, %{"content" => record}} <-
             FiskalyUnified.get(connection, token, "/records/" <> URI.encode_www_form(record_id)) do
        signature(connection, record)
      else
        # A read is always safe to repeat.
        {:error, {:uncertain, reason}} -> {:error, {:transient, reason}}
        {:ok, _unexpected} -> {:error, {:transient, :unexpected_answer}}
        error -> error
      end
    end)
  end

  defp operation(schema, vat) do
    schema = atomize(schema)

    with {:ok, number} <- number(schema),
         {:ok, body} <-
           FiskalyUnified.operation_body(schema, vat, returns: schema.kind == "credit_note") do
      receipt =
        Map.merge(body, %{
          type: "RECEIPT",
          document: receipt_document(schema, number),
          customer: %{type: "EXTERNAL"}
        })

      case schema.kind do
        "credit_note" ->
          {:ok,
           %{
             type: "CORRECTION",
             record: %{id: schema.original_record_id},
             reason: String.slice("Avoir #{schema.number}", 0, 128),
             data: receipt
           }}

        _receipt ->
          {:ok, receipt}
      end
    end
  end

  defp receipt_document(schema, number) do
    %{number: number, issued_at: FiskalyUnified.timestamp(schema.issued_at)}
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
    |> then(fn document ->
      if schema[:offline],
        do: Map.put(document, :offline, %{reason: "Connexion interrompue", reference: number}),
        else: document
    end)
  end

  defp number(schema) do
    case FiskalyUnified.document_number(schema.number) do
      nil ->
        {:error,
         {:rejected,
          [%{code: "document_number_format", message: "fiskaly needs [0-9A-Z_/-.]{1,20}"}]}}

      number ->
        {:ok, number}
    end
  end

  defp signature(_connection, %{"state" => state} = record) when state in ["REJECTED", "FAILED"],
    do: {:error, {:rejected, FiskalyUnified.log_errors(record)}}

  defp signature(connection, %{"id" => id} = record) do
    sequence = get_in(record, ["compliance", "sequence"]) || %{}
    journal = record["journal"] || %{}
    value = sequence["signature"] || journal["signature"]

    if is_binary(value) and value != "" do
      {:ok,
       %{
         transaction_number: integer(sequence["number"]),
         signature_counter: integer(sequence["number"]),
         signature_value: value,
         signature_algorithm: nil,
         time_format: nil,
         started_at_device: nil,
         finished_at_device: time(journal["signed_at"]),
         unit_serial: connection[:unit_serial],
         register_serial: connection[:register_serial],
         receipt_number: id,
         qr_code_data: get_in(record, ["compliance", "qr_code"]),
         device_failed: false,
         hint: nil
       }}
    else
      # Accepted but not signed yet: read back later, never sent again.
      {:error, {:uncertain, :signature_missing}}
    end
  end

  defp signature(_connection, _record), do: {:error, {:uncertain, :record_id_missing}}

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> nil
    end
  end

  defp integer(_value), do: nil

  defp time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> %{time | microsecond: {elem(time.microsecond, 0), 6}}
      _error -> nil
    end
  end

  defp time(_value), do: nil

  defp system_id(%{register_serial: id}) when is_binary(id) and id != "", do: {:ok, id}

  defp system_id(_connection),
    do: {:error, {:rejected, [%{code: "not_provisioned", message: "No fiskaly System yet"}]}}

  # ── HTTP ────────────────────────────────────────────────────────────────

  # Runs `steps` with a fresh token; the wire log keeps the last answer and
  # only the request data given (never the credentials or the token).
  defp run(connection, logged, steps) do
    FiskalyUnified.reset()

    result =
      with :ok <- FiskalyUnified.credentials(connection),
           {:ok, token} <- FiskalyUnified.token(connection) do
        steps.(token)
      end

    {status, body} = FiskalyUnified.take_last_response()
    {normalize(result), Http.wire(logged && Jason.encode!(logged), status, body)}
  end

  defp normalize({:error, {:not_found, _body}}),
    do: {:error, {:rejected, [%{code: "not_found", message: "Unknown at fiskaly"}]}}

  defp normalize(result), do: result

  defp atomize(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), atomize_value(value)}
      {key, value} -> {key, atomize_value(value)}
    end)
  end

  defp atomize_value(list) when is_list(list), do: Enum.map(list, &atomize_value/1)
  defp atomize_value(%{__struct__: _} = struct), do: struct
  defp atomize_value(map) when is_map(map), do: atomize(map)
  defp atomize_value(value), do: value
end
