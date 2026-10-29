defmodule Palee.Fiscal.Reporting do
  @moduledoc """
  Reporting fiscal documents to the tax authority (ADR-243): today the
  Greek myDATA, through the `Fiscal.Ports.AuthorityGateway` of the
  organization's connection environment.

  Issuing a document in a country whose profile names an authority adds a
  `pending` transmission in the same transaction (`enqueue/3`), so a
  document is never issued without its outbox row. Workers then claim due
  rows, map the document (`Domain.MyDataInvoice`), call the gateway outside
  any transaction, and record the attempt, the new state and (once
  accepted) a `document_reported` journal entry with the MARK.

  The document never changes: the MARK, UID and QR link live on the
  transmission and are printed from there.
  """

  alias Palee.Fiscal
  alias Palee.Fiscal.{Connections, FiscalStore, TransmissionStore}
  alias Palee.Fiscal.Domain.{CountryProfile, MyDataInvoice, TransmissionPolicy}

  @authority "mydata"
  @environments ~w(sandbox test production)
  @batch 25

  def environments, do: @environments

  defp gateway(environment) do
    :palee
    |> Application.fetch_env!(:fiscal_authority_gateways)
    |> Map.fetch!(environment)
  end

  # ── Outbox ──────────────────────────────────────────────────────────────

  @doc false
  # Inside the issuing transaction.
  def enqueue(context, document, %DateTime{} = now) do
    with {:ok, profile} <- CountryProfile.fetch(document.country_code) do
      if TransmissionPolicy.required?(profile) do
        context
        |> TransmissionStore.insert_transmission(%{
          document_id: document.id,
          authority: Atom.to_string(profile.authority),
          status: "pending",
          next_attempt_at: now
        })
        |> case do
          {:ok, _transmission} -> :ok
          error -> error
        end
      else
        :ok
      end
    end
  end

  @doc "The transmission of each document id that has one."
  def transmissions_for(context, document_ids),
    do: TransmissionStore.transmissions_for_documents(context, document_ids)

  @doc "Transmissions (newest first) with counts per status; filters: status, limit, offset."
  def list(context, filters \\ %{}), do: TransmissionStore.list_transmissions(context, filters)

  @doc "A transmission with its attempts."
  def get(context, id) do
    case TransmissionStore.get_transmission(context, id) do
      nil ->
        nil

      transmission ->
        Map.put(transmission, :attempts_log, TransmissionStore.list_attempts(context, id))
    end
  end

  @doc """
  Sends what is due (or only `id`): `{:ok, %{accepted, rejected, failed,
  deferred, retrying}}` (counts). Safe to run from several workers at once.
  """
  def transmit(context, which \\ :due, %DateTime{} = now) do
    context
    |> TransmissionStore.claim(which, now, @batch)
    |> Enum.map(&transmit_one(context, &1, now))
    |> Enum.frequencies()
    |> then(
      &{:ok, Map.merge(%{accepted: 0, rejected: 0, failed: 0, deferred: 0, retrying: 0}, &1)}
    )
  end

  defp transmit_one(context, transmission, now) do
    connection = TransmissionStore.get_connection(context, transmission.authority)
    document = FiscalStore.get_document(context, transmission.document_id, [])

    cond do
      is_nil(connection) ->
        defer(context, transmission, :connection_missing, now)

      connection.status == "invalid" ->
        defer(context, transmission, :connection_invalid, now)

      true ->
        case original(context, document) do
          {:wait, _original} -> defer(context, transmission, :original_not_accepted, now)
          {:ok, original} -> submit(context, transmission, connection, document, original, now)
        end
    end
  end

  # A credit note goes after the document it corrects has its MARK.
  defp original(_context, %{corrects_document_id: nil}), do: {:ok, nil}

  defp original(context, %{corrects_document_id: original_id}) do
    original = FiscalStore.get_document(context, original_id, [])

    case TransmissionStore.transmissions_for_documents(context, [original_id]) do
      %{^original_id => %{status: "accepted", mark: mark}} ->
        {:ok, %{kind: original.kind, mark: mark}}

      %{^original_id => _waiting} ->
        {:wait, original}

      %{} ->
        {:ok, %{kind: original.kind, mark: nil}}
    end
  end

  defp submit(context, transmission, connection, document, original, now) do
    started = System.monotonic_time(:millisecond)

    {result, wire} =
      case MyDataInvoice.build(document, original: original) do
        {:ok, invoice} ->
          gateway(connection.environment).submit(connection, invoice)

        {:error, reason} ->
          {{:error, {:rejected, [%{code: Atom.to_string(reason), message: "palee"}]}},
           %{request_body: nil, response_status: nil, response_body: nil}}
      end

    changes =
      transmission
      |> TransmissionPolicy.outcome(result, now)
      |> Map.put(:environment, connection.environment)

    attempt =
      Map.merge(wire, %{
        attempt: transmission.attempts,
        environment: connection.environment,
        outcome: TransmissionPolicy.attempt_outcome(result),
        error: error_text(result),
        duration_ms: System.monotonic_time(:millisecond) - started,
        started_at: now
      })

    with {:ok, _saved} <- record(context, transmission, document, changes, attempt, now) do
      if match?({:error, {:unauthorized, _}}, result) do
        Connections.mark_invalid(
          context,
          "mydata",
          "credentials_rejected",
          error_text(result),
          now
        )
      end

      case changes.status do
        "accepted" -> :accepted
        "rejected" -> :rejected
        "failed" -> :failed
        _pending -> :retrying
      end
    else
      _error -> :retrying
    end
  end

  defp record(context, transmission, document, %{status: "accepted"} = changes, attempt, now) do
    FiscalStore.transaction(context, fn ->
      with {:ok, saved} <- TransmissionStore.finish(context, transmission.id, changes, attempt),
           {:ok, _entry} <-
             Fiscal.append(context, %{
               event_type: "document_reported",
               subject_type: "fiscal_document",
               subject_id: document.id,
               actor_id: nil,
               occurred_at: now,
               payload: %{
                 authority: transmission.authority,
                 environment: changes.environment,
                 number: document.number,
                 mark: changes.mark,
                 uid: changes.uid,
                 authentication_code: changes.authentication_code
               }
             }) do
        {:ok, saved}
      end
    end)
  end

  defp record(context, transmission, _document, changes, attempt, _now),
    do: TransmissionStore.finish(context, transmission.id, changes, attempt)

  defp defer(context, transmission, reason, now) do
    TransmissionStore.update_transmission(
      context,
      transmission.id,
      TransmissionPolicy.deferral(transmission, reason, now)
    )

    :deferred
  end

  defp error_text({:ok, _receipt}), do: nil
  defp error_text({:error, reason}), do: reason |> inspect() |> String.slice(0, 1_000)

  @doc """
  Staff send a rejected or failed document again (after fixing the cause).
  `{:ok, transmission}` or `{:error, :not_retryable | :not_found}`.
  """
  def retry(context, document_id, %DateTime{} = now) do
    case TransmissionStore.transmissions_for_documents(context, [document_id]) do
      %{^document_id => transmission} ->
        if TransmissionPolicy.retryable?(transmission),
          do:
            TransmissionStore.update_transmission(
              context,
              transmission.id,
              TransmissionPolicy.retry(now)
            ),
          else: {:error, :not_retryable}

      %{} ->
        {:error, :not_found}
    end
  end

  # ── Connection ──────────────────────────────────────────────────────────

  @doc "The connection as shown to staff (never the key)."
  def connection(context) do
    context
    |> TransmissionStore.get_connection(@authority)
    |> public_connection()
  end

  defp public_connection(nil), do: nil

  defp public_connection(connection) do
    connection
    |> Map.take([:authority, :environment, :user_id, :status, :updated_at])
    |> Map.merge(Connections.public_check(connection))
    |> Map.put(:has_subscription_key, is_binary(connection.subscription_key))
  end

  @doc false
  # ADR-273: «Δοκιμή σύνδεσης» with the connection's own credentials.
  def check_connection(connection), do: gateway(connection.environment).check(connection)

  @doc """
  Saves the myDATA connection. `test` and `production` need the
  business's myDATA user and subscription key; a saved user or key is
  kept when none is sent. Journals the change (without the key) and wakes
  the documents that were waiting for it.
  """
  def save_connection(context, params, actor_id, %DateTime{} = now) do
    before = TransmissionStore.get_connection(context, @authority)

    with {:ok, attrs} <- validate_connection(before, params) do
      FiscalStore.transaction(context, fn ->
        with {:ok, saved} <-
               TransmissionStore.save_connection(
                 context,
                 @authority,
                 attrs
                 |> Map.merge(Connections.saved_fields())
                 |> Map.merge(%{
                   updated_by_id: actor_id,
                   updated_by_platform: params[:updated_by_platform] == true
                 })
               ),
             {:ok, _entry} <-
               Fiscal.append(context, %{
                 event_type: "authority_connection_saved",
                 subject_type: "authority_connection",
                 subject_id: saved.id,
                 actor_id: actor_id,
                 occurred_at: now,
                 payload: %{
                   authority: @authority,
                   environment: saved.environment,
                   user_id: saved.user_id,
                   key_changed: Map.has_key?(attrs, :subscription_key)
                 }
                 |> Connections.platform_mark(params)
               }) do
          TransmissionStore.wake_waiting(context, now)
          {:ok, public_connection(saved)}
        end
      end)
    end
  end

  defp validate_connection(before, params) do
    environment = params[:environment]
    user_id = clean(params[:user_id]) || (before && before.user_id)
    key = params[:subscription_key] |> clean()
    stored_key = before && before.subscription_key

    errors =
      %{}
      |> add_error(environment not in @environments, :environment, "invalid")
      |> add_error(
        environment in ["test", "production"] and is_nil(user_id),
        :user_id,
        "required"
      )
      |> add_error(
        environment in ["test", "production"] and is_nil(key) and is_nil(stored_key),
        :subscription_key,
        "required"
      )
      |> add_error(is_binary(user_id) and String.length(user_id) > 100, :user_id, "too_long")
      |> add_error(is_binary(key) and String.length(key) > 200, :subscription_key, "too_long")

    if errors == %{} do
      {:ok,
       %{environment: environment, user_id: user_id}
       |> then(fn attrs -> if key, do: Map.put(attrs, :subscription_key, key), else: attrs end)}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

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
