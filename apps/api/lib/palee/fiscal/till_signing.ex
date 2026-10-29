defmodule Palee.Fiscal.TillSigning do
  @moduledoc """
  Signing till receipts with the cash-register security device of the
  business's country (ADR-251): a cloud TSE in Germany, an RKSV signature
  creation unit in Austria, through the `Fiscal.Ports.CashRegisterSecurity`
  adapter of the organization's connection.

  Issuing a till transaction in such a country (a receipt, an invoice
  paid at the till in cash or by card, or a credit note correcting one of
  them; `TillSigningPolicy.required?/3`) adds a `pending` signature in the
  same transaction (`enqueue/3`). The signature row's kind is `receipt`
  for all of them: DSFinV-K's process type `Beleg` (`Kassenbeleg-V1`).
  Workers then claim due rows, call the device outside any transaction
  (an uncertain row is only read back), and record the attempt and the
  signature data. The document never changes: its signature lives on the
  signature row and is printed from there (`print/1`). Every signature
  and every device failure is journaled (`receipt_signed`,
  `till_device_failed`), which is also how a German TSE failure is
  documented.
  """

  alias Palee.Fiscal
  alias Palee.Fiscal.{FiscalStore, TillSignatureStore}

  alias Palee.Fiscal.Domain.{
    CountryProfile,
    RksvReceipt,
    TillSigningPolicy,
    TseTransaction
  }

  @devices ~w(tse rksv)
  @environments ~w(sandbox test production)
  @batch 25

  def devices, do: @devices
  def environments, do: @environments

  defp adapter(device, provider) do
    :palee
    |> Application.fetch_env!(:fiscal_cash_register_security)
    |> Map.fetch!({device, provider})
  end

  # ── Outbox ──────────────────────────────────────────────────────────────

  @doc false
  # Inside the issuing transaction.
  def enqueue(context, document, %DateTime{} = now) do
    with {:ok, profile} <- CountryProfile.fetch(document.country_code),
         device when is_binary(device) <- TillSigningPolicy.device(profile),
         true <- TillSigningPolicy.required?(profile, document, original(context, document)) do
      context
      |> TillSignatureStore.insert_signature(%{
        document_id: document.id,
        device: device,
        kind: "receipt",
        status: "pending",
        next_attempt_at: now,
        external_id: Ecto.UUID.generate()
      })
      |> case do
        {:ok, _signature} -> :ok
        error -> error
      end
    else
      _not_signed -> :ok
    end
  end

  defp original(_context, %{corrects_document_id: nil}), do: nil

  defp original(context, %{corrects_document_id: id}),
    do: FiscalStore.get_document(context, id, [])

  @doc "The signature of each document id that has one."
  def signatures_for(context, document_ids),
    do: TillSignatureStore.signatures_for_documents(context, document_ids)

  @doc "Signatures (newest first) with counts per status; filters: status, device, limit, offset."
  def list(context, filters \\ %{}), do: TillSignatureStore.list_signatures(context, filters)

  @doc "A signature with its attempts."
  def get(context, id) do
    case TillSignatureStore.get_signature(context, id) do
      nil ->
        nil

      signature ->
        Map.put(signature, :attempts_log, TillSignatureStore.list_attempts(context, id))
    end
  end

  @doc "What a receipt prints for its signature: `[%{label, value}]`."
  def print(%{device: "tse"} = signature), do: lines(TseTransaction.print_lines(signature))
  def print(%{device: "rksv"} = signature), do: lines(RksvReceipt.print_lines(signature))
  def print(_signature), do: []

  defp lines(pairs), do: Enum.map(pairs, fn {label, value} -> %{label: label, value: value} end)

  @doc """
  Signs (or reads back) what is due, or only `id`: `{:ok, counts}` with
  `signed, device_failed, rejected, failed, uncertain, deferred,
  retrying`. Safe to run from several workers at once.
  """
  def transmit(context, which \\ :due, %DateTime{} = now) do
    context
    |> TillSignatureStore.claim(which, now, @batch)
    |> Enum.map(&handle(context, &1, now))
    |> Enum.frequencies()
    |> then(
      &{:ok,
       Map.merge(
         %{
           signed: 0,
           device_failed: 0,
           rejected: 0,
           failed: 0,
           uncertain: 0,
           deferred: 0,
           retrying: 0
         },
         &1
       )}
    )
  end

  defp handle(context, signature, now) do
    connection = TillSignatureStore.get_connection(context, signature.device)

    document =
      signature.document_id && FiscalStore.get_document(context, signature.document_id, [])

    issued_at = document && document.issued_at

    cond do
      TillSigningPolicy.operation(signature, now, issued_at) == :fail ->
        record(
          context,
          signature,
          connection,
          document,
          TillSigningPolicy.tse_failure(now, "not_signed_in_time"),
          nil,
          now
        )

      is_nil(connection) or connection.status != "active" ->
        reason = if is_nil(connection), do: :connection_missing, else: :connection_invalid
        defer(context, signature, reason, now)

      true ->
        call(context, signature, connection, document, issued_at, now)
    end
  end

  defp call(context, signature, connection, document, issued_at, now) do
    started = System.monotonic_time(:millisecond)
    operation = if signature.status == "uncertain", do: :lookup, else: :sign

    {result, wire} =
      case schema(signature, document) do
        {:ok, schema} ->
          request = %{external_id: signature.external_id, kind: signature.kind, schema: schema}
          apply(adapter(connection.device, connection.provider), operation, [connection, request])

        {:error, reason} ->
          {{:error, {:rejected, [%{code: Atom.to_string(reason), message: "palee"}]}},
           %{request_body: nil, response_status: nil, response_body: nil}}
      end

    changes =
      signature
      |> TillSigningPolicy.outcome(result, now, issued_at: issued_at)
      |> Map.put(:environment, connection.environment)

    attempt =
      Map.merge(wire, %{
        attempt: max(signature.attempts, 1),
        operation: Atom.to_string(operation),
        environment: connection.environment,
        outcome: TillSigningPolicy.attempt_outcome(result),
        error: error_text(result),
        duration_ms: System.monotonic_time(:millisecond) - started,
        started_at: now
      })

    if match?({:error, {:unauthorized, _}}, result),
      do:
        TillSignatureStore.set_connection_status(
          context,
          connection.device,
          "invalid",
          error_text(result)
        )

    record(context, signature, connection, document, changes, attempt, now)
  end

  defp schema(%{kind: "receipt", device: "tse"}, document), do: TseTransaction.schema(document)
  defp schema(%{kind: "receipt", device: "rksv"}, document), do: RksvReceipt.schema(document)
  defp schema(_special, _document), do: {:ok, RksvReceipt.null_schema()}

  defp record(context, signature, connection, document, %{status: status} = changes, attempt, now)
       when status in ["signed", "device_failed"] do
    FiscalStore.transaction(context, fn ->
      with {:ok, saved} <- TillSignatureStore.finish(context, signature.id, changes, attempt),
           {:ok, _entry} <-
             Fiscal.append(context, %{
               event_type:
                 if(status == "signed", do: "receipt_signed", else: "till_device_failed"),
               subject_type: if(document, do: "fiscal_document", else: "till_signature"),
               subject_id: if(document, do: document.id, else: signature.id),
               actor_id: nil,
               occurred_at: now,
               payload: %{
                 device: signature.device,
                 kind: signature.kind,
                 environment: connection && connection.environment,
                 number: document && document.number,
                 transaction_number: saved.transaction_number,
                 signature_counter: saved.signature_counter,
                 receipt_number: saved.receipt_number,
                 unit_serial: saved.unit_serial,
                 register_serial: saved.register_serial,
                 reason: saved.last_error_message
               }
             }) do
        {:ok, saved}
      end
    end)
    |> case do
      {:ok, _saved} -> String.to_atom(status)
      _error -> :retrying
    end
  end

  defp record(context, signature, _connection, _document, changes, attempt, _now) do
    case TillSignatureStore.finish(context, signature.id, changes, attempt) do
      {:ok, %{status: "rejected"}} -> :rejected
      {:ok, %{status: "failed"}} -> :failed
      {:ok, %{status: "uncertain"}} -> :uncertain
      _pending -> :retrying
    end
  end

  defp defer(context, signature, reason, now) do
    TillSignatureStore.update_signature(
      context,
      signature.id,
      TillSigningPolicy.deferral(signature, reason, now)
    )

    :deferred
  end

  defp error_text({:ok, _result}), do: nil
  defp error_text({:error, reason}), do: reason |> inspect() |> String.slice(0, 1_000)

  @doc """
  Staff try a refused, failed, uncertain or failed-device row again.
  `{:ok, signature}` or `{:error, :not_retryable | :not_found}`.
  """
  def retry(context, id, %DateTime{} = now) do
    case TillSignatureStore.get_signature(context, id) do
      nil ->
        {:error, :not_found}

      signature ->
        if TillSigningPolicy.retryable?(signature) and
             not (signature.device == "tse" and signature.status == "device_failed"),
           do:
             TillSignatureStore.update_signature(
               context,
               signature.id,
               TillSigningPolicy.retry(signature, now)
             ),
           else: {:error, :not_retryable}
    end
  end

  @doc """
  Queues an RKSV null receipt (Nullbeleg), e.g. for a monthly check or
  after the till was out of use. `{:ok, signature}` or
  `{:error, :till_not_connected}`.
  """
  def null_receipt(context, %DateTime{} = now) do
    case TillSignatureStore.get_connection(context, "rksv") do
      %{status: "active"} ->
        TillSignatureStore.insert_signature(context, %{
          device: "rksv",
          kind: "null",
          status: "pending",
          next_attempt_at: now,
          external_id: Ecto.UUID.generate()
        })

      _other ->
        {:error, :till_not_connected}
    end
  end

  # ── Connection ──────────────────────────────────────────────────────────

  @doc "The connection as shown to staff (never the key, secret or PIN)."
  def connection(context, device) when device in @devices do
    context
    |> TillSignatureStore.get_connection(device)
    |> public_connection()
  end

  defp public_connection(nil), do: nil

  defp public_connection(connection) do
    connection
    |> Map.take([
      :device,
      :provider,
      :environment,
      :unit_id,
      :register_id,
      :unit_serial,
      :register_serial,
      :public_key,
      :provisioned_at,
      :status,
      :last_error,
      :updated_at
    ])
    |> Map.merge(%{
      has_api_key: is_binary(connection.api_key),
      has_api_secret: is_binary(connection.api_secret)
    })
  end

  @doc """
  Saves the till connection of `device` and, when it is new, has changed
  environment or `reprovision` is true, creates and initialises a new
  unit and register at the provider (outside any transaction), then
  journals the change (never the credentials) and wakes waiting receipts.
  `test` and `production` go through fiskaly and need the API key and
  secret; saved ones are kept when none are sent.
  """
  def save_connection(context, device, params, actor_id, %DateTime{} = now)
      when device in @devices do
    before = TillSignatureStore.get_connection(context, device)
    identity = FiscalStore.get_identity(context)

    with {:ok, attrs} <- validate_connection(before, identity, device, params) do
      provision? =
        is_nil(before) or before.status != "active" or before.environment != attrs.environment or
          params[:reprovision] == true

      if provision?,
        do: provision(context, device, before, identity, attrs, actor_id, now),
        else: store(context, device, attrs, actor_id, nil, now)
    end
  end

  defp provision(context, device, before, identity, attrs, actor_id, now) do
    ids = %{unit_id: Ecto.UUID.generate(), register_id: Ecto.UUID.generate()}
    secrets = Map.take(before || %{}, [:api_key, :api_secret])

    connection =
      secrets
      |> Map.merge(attrs)
      |> Map.merge(ids)
      |> Map.merge(%{device: device, admin_pin: nil})

    # The new ids are saved before the provider is called, so a retry after
    # a lost answer never leaves a unit Palee does not know about.
    pending =
      Map.merge(attrs, ids)
      |> Map.merge(%{status: "provisioning", provisioned_at: nil, updated_by_id: actor_id})

    with {:ok, _saved} <- TillSignatureStore.save_connection(context, device, pending) do
      provider_context = %{
        legal_name: identity && identity.legal_name,
        vat_number: identity && identity.vat_number,
        register_serial: "PALEE-" <> String.slice(ids.register_id, 0, 8)
      }

      {result, _wire} = adapter(device, attrs.provider).provision(connection, provider_context)

      case result do
        {:ok, provisioned} ->
          store(
            context,
            device,
            Map.merge(attrs, %{
              unit_serial: provisioned.unit_serial,
              register_serial: provisioned.register_serial,
              public_key: provisioned.public_key,
              admin_pin: provisioned.admin_pin,
              provisioned_at: now
            }),
            actor_id,
            provisioned.start,
            now
          )

        {:error, reason} ->
          message = reason |> inspect() |> String.slice(0, 500)
          TillSignatureStore.set_connection_status(context, device, "provisioning", message)

          case reason do
            {:unauthorized, _} -> {:error, :till_credentials_refused}
            _other -> {:error, :till_provisioning_failed}
          end
      end
    end
  end

  defp store(context, device, attrs, actor_id, start, now) do
    FiscalStore.transaction(context, fn ->
      with {:ok, saved} <-
             TillSignatureStore.save_connection(
               context,
               device,
               Map.merge(attrs, %{status: "active", last_error: nil, updated_by_id: actor_id})
             ),
           :ok <- store_start(context, device, saved, start, now),
           {:ok, _entry} <-
             Fiscal.append(context, %{
               event_type: "till_connection_saved",
               subject_type: "till_connection",
               subject_id: saved.id,
               actor_id: actor_id,
               occurred_at: now,
               payload: %{
                 device: device,
                 provider: saved.provider,
                 environment: saved.environment,
                 unit_id: saved.unit_id,
                 register_id: saved.register_id,
                 unit_serial: saved.unit_serial,
                 register_serial: saved.register_serial,
                 key_changed: Map.has_key?(attrs, :api_key) or Map.has_key?(attrs, :api_secret)
               }
             }) do
        TillSignatureStore.wake_waiting(context, now)
        {:ok, public_connection(saved)}
      end
    end)
  end

  defp store_start(_context, _device, _saved, nil, _now), do: :ok

  defp store_start(context, device, saved, start, now) do
    context
    |> TillSignatureStore.insert_signature(
      start
      |> Map.drop([:device_failed, :hint])
      |> Map.merge(%{
        device: device,
        kind: "start",
        period: DateTime.to_date(now),
        status: "signed",
        signed_at: now,
        environment: saved.environment,
        external_id: Ecto.UUID.generate()
      })
    )
    |> case do
      {:ok, _start} -> :ok
      error -> error
    end
  end

  defp validate_connection(before, identity, device, params) do
    environment = params[:environment]
    sandbox? = environment == "sandbox"
    key = clean(params[:api_key])
    secret = clean(params[:api_secret])

    expected =
      identity && identity.country_code |> CountryProfile.fetch!() |> TillSigningPolicy.device()

    errors =
      %{}
      |> add_error(environment not in @environments, :environment, "invalid")
      |> add_error(expected != device, :device, "not_for_country")
      |> add_error(
        not sandbox? and is_nil(key) and is_nil(before && before.api_key),
        :api_key,
        "required"
      )
      |> add_error(
        not sandbox? and is_nil(secret) and is_nil(before && before.api_secret),
        :api_secret,
        "required"
      )
      |> add_error(is_binary(key) and String.length(key) > 200, :api_key, "too_long")
      |> add_error(is_binary(secret) and String.length(secret) > 200, :api_secret, "too_long")

    if errors == %{} do
      {:ok,
       %{environment: environment, provider: if(sandbox?, do: "sandbox", else: "fiskaly")}
       |> put_present(:api_key, if(sandbox?, do: nil, else: key))
       |> put_present(:api_secret, if(sandbox?, do: nil, else: secret))}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp add_error(errors, true, field, code), do: Map.put(errors, field, [code])
  defp add_error(errors, false, _field, _code), do: errors

  defp clean(nil), do: nil

  defp clean(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp clean(_value), do: nil
end
