defmodule Palee.Fiscal.EInvoicing do
  @moduledoc """
  Sending B2B invoices and credit notes over Peppol (ADR-250), through the
  `Fiscal.Ports.EInvoiceNetwork` of the organization's connection
  environment.

  Issuing an invoice (or a credit note correcting one) in a country whose
  profile names Peppol, to a buyer with a Peppol address (its own
  `peppol_id`, or the `0208` enterprise number of a Belgian VAT number),
  adds a `pending` submission in the same transaction (`enqueue/3`).
  Workers then claim due rows, map the document to UBL
  (`Domain.UblInvoice`), call the access point outside any transaction,
  record the attempt and the new state, and poll the delivery until the
  receiver's access point acknowledges it; a `document_delivered` journal
  entry records each delivery.

  The document never changes: the submission id and the delivery state
  live on the submission.
  """

  alias Palee.Fiscal
  alias Palee.Fiscal.{EInvoiceStore, FiscalStore}
  alias Palee.Fiscal.Domain.{CountryProfile, EInvoicePolicy, PeppolId, UblInvoice}

  @network "peppol"
  @environments ~w(sandbox test production)
  @batch 25

  def network, do: @network
  def environments, do: @environments

  defp adapter(provider) do
    :palee
    |> Application.fetch_env!(:fiscal_einvoice_networks)
    |> Map.fetch!(provider)
  end

  # ── Outbox ──────────────────────────────────────────────────────────────

  @doc false
  # Inside the issuing transaction.
  def enqueue(context, document, %DateTime{} = now) do
    with {:ok, profile} <- CountryProfile.fetch(document.country_code),
         true <- EInvoicePolicy.required?(profile, document),
         {:ok, recipient} <- PeppolId.for_party(atom_keys(document.buyer)) do
      context
      |> EInvoiceStore.insert_submission(%{
        document_id: document.id,
        network: @network,
        status: "pending",
        next_attempt_at: now,
        idempotency_guid: Ecto.UUID.generate(),
        recipient_scheme: recipient.scheme,
        recipient_identifier: recipient.identifier
      })
      |> case do
        {:ok, _submission} -> :ok
        error -> error
      end
    else
      # Not a Peppol document (another country, a receipt, a consumer).
      _not_sent -> :ok
    end
  end

  @doc "The submission of each document id that has one."
  def submissions_for(context, document_ids),
    do: EInvoiceStore.submissions_for_documents(context, document_ids)

  @doc "Submissions (newest first) with counts per status; filters: status, limit, offset."
  def list(context, filters \\ %{}), do: EInvoiceStore.list_submissions(context, filters)

  @doc "A submission with its attempts."
  def get(context, id) do
    case EInvoiceStore.get_submission(context, id) do
      nil -> nil
      submission -> Map.put(submission, :attempts_log, EInvoiceStore.list_attempts(context, id))
    end
  end

  @doc """
  Sends and polls what is due (or only `id`): `{:ok, counts}` with
  `submitted, delivered, rejected, failed, uncertain, deferred, retrying,
  polling`. Safe to run from several workers at once.
  """
  def transmit(context, which \\ :due, %DateTime{} = now) do
    context
    |> EInvoiceStore.claim(which, now, @batch)
    |> Enum.map(&handle(context, &1, now))
    |> Enum.frequencies()
    |> then(
      &{:ok,
       Map.merge(
         %{
           submitted: 0,
           delivered: 0,
           rejected: 0,
           failed: 0,
           uncertain: 0,
           deferred: 0,
           retrying: 0,
           polling: 0
         },
         &1
       )}
    )
  end

  defp handle(context, submission, now) do
    connection = EInvoiceStore.get_connection(context, @network)

    cond do
      is_nil(connection) and submission.status == "sending" ->
        defer(context, submission, :connection_missing, now)

      is_nil(connection) ->
        :polling

      connection.status == "invalid" and submission.status == "sending" ->
        defer(context, submission, :connection_invalid, now)

      submission.status == "sending" ->
        submit(context, submission, connection, now)

      true ->
        poll(context, submission, connection, now)
    end
  end

  defp submit(context, submission, connection, now) do
    started = System.monotonic_time(:millisecond)
    document = FiscalStore.get_document(context, submission.document_id, [])

    {result, wire} =
      case ubl(context, document, connection, submission) do
        {:ok, ubl} ->
          adapter(connection.provider).submit(connection, %{
            ubl: ubl,
            document_type: UblInvoice.document_type(document),
            idempotency_guid: submission.idempotency_guid,
            recipient: %{
              scheme: submission.recipient_scheme,
              identifier: submission.recipient_identifier
            }
          })

        {:error, reason} ->
          {{:error, {:rejected, [%{code: Atom.to_string(reason), message: "palee"}]}},
           %{request_body: nil, response_status: nil, response_body: nil}}
      end

    changes =
      submission
      |> EInvoicePolicy.submit_outcome(result, now)
      |> Map.put(:environment, connection.environment)

    attempt = attempt(:submit, submission.attempts, connection, result, wire, started, now)

    with {:ok, _saved} <- EInvoiceStore.finish(context, submission.id, changes, attempt) do
      invalidate(context, result)

      case changes.status do
        "submitted" -> :submitted
        "rejected" -> :rejected
        "failed" -> :failed
        "uncertain" -> :uncertain
        _pending -> :retrying
      end
    else
      _error -> :retrying
    end
  end

  defp ubl(context, document, connection, submission) do
    original =
      case document.corrects_document_id do
        nil ->
          nil

        id ->
          case FiscalStore.get_document(context, id, []) do
            nil -> nil
            original -> %{number: original.number, issue_date: original.issue_date}
          end
      end

    UblInvoice.build(document,
      seller_endpoint: %{
        scheme: connection.peppol_scheme,
        identifier: connection.peppol_identifier
      },
      buyer_endpoint: %{
        scheme: submission.recipient_scheme,
        identifier: submission.recipient_identifier
      },
      original: original
    )
  end

  defp poll(context, submission, connection, now) do
    started = System.monotonic_time(:millisecond)

    {result, wire} =
      adapter(connection.provider).status(connection, submission.provider_submission_id)

    changes = EInvoicePolicy.poll_outcome(submission, result, now)

    attempt = attempt(:status, submission.attempts, connection, result, wire, started, now)

    with {:ok, _saved} <- record_poll(context, submission, changes, attempt, now) do
      invalidate(context, result)

      case changes.status do
        "delivered" -> :delivered
        "rejected" -> :rejected
        "failed" -> :failed
        _submitted -> :polling
      end
    else
      _error -> :polling
    end
  end

  defp record_poll(context, submission, %{status: "delivered"} = changes, attempt, now) do
    document = FiscalStore.get_document(context, submission.document_id, [])

    FiscalStore.transaction(context, fn ->
      with {:ok, saved} <- EInvoiceStore.finish(context, submission.id, changes, attempt),
           {:ok, _entry} <-
             Fiscal.append(context, %{
               event_type: "document_delivered",
               subject_type: "fiscal_document",
               subject_id: submission.document_id,
               actor_id: nil,
               occurred_at: now,
               payload: %{
                 network: @network,
                 environment: submission.environment,
                 number: document && document.number,
                 recipient: "#{submission.recipient_scheme}:#{submission.recipient_identifier}",
                 provider_submission_id: submission.provider_submission_id
               }
             }) do
        {:ok, saved}
      end
    end)
  end

  defp record_poll(context, submission, changes, attempt, _now),
    do: EInvoiceStore.finish(context, submission.id, changes, attempt)

  defp attempt(operation, number, connection, result, wire, started, now) do
    Map.merge(wire, %{
      attempt: max(number, 1),
      operation: Atom.to_string(operation),
      environment: connection.environment,
      outcome: EInvoicePolicy.attempt_outcome(operation, result),
      error: error_text(result),
      duration_ms: System.monotonic_time(:millisecond) - started,
      started_at: now
    })
  end

  defp invalidate(context, {:error, {:unauthorized, _reason}} = result),
    do: EInvoiceStore.set_connection_status(context, @network, "invalid", error_text(result))

  defp invalidate(_context, _result), do: :ok

  defp defer(context, submission, reason, now) do
    EInvoiceStore.update_submission(
      context,
      submission.id,
      EInvoicePolicy.deferral(submission, reason, now)
    )

    :deferred
  end

  defp error_text({:ok, _result}), do: nil
  defp error_text({:error, reason}), do: reason |> inspect() |> String.slice(0, 1_000)

  @doc """
  Staff send a refused, failed or uncertain document again (after fixing
  the cause, or after checking the access point's portal for an uncertain
  one). `{:ok, submission}` or `{:error, :not_retryable | :not_found}`.
  """
  def retry(context, document_id, %DateTime{} = now) do
    case EInvoiceStore.submissions_for_documents(context, [document_id]) do
      %{^document_id => submission} ->
        if EInvoicePolicy.retryable?(submission),
          do:
            EInvoiceStore.update_submission(
              context,
              submission.id,
              EInvoicePolicy.retry(submission, now)
            ),
          else: {:error, :not_retryable}

      %{} ->
        {:error, :not_found}
    end
  end

  @doc """
  A webhook from the access point (authenticated by the connection's
  secret token): makes the delivery poll of each submission it names due
  now. The body itself is never trusted. `:ok` or `{:error, :not_found}`.
  """
  def webhook(context, token, body, %DateTime{} = now) when is_binary(token) do
    with %{webhook_token_hash: hash} when is_binary(hash) <-
           EInvoiceStore.get_connection(context, @network),
         true <- Plug.Crypto.secure_compare(hash, token_hash(token)) do
      body
      |> submission_ids()
      |> Enum.each(&EInvoiceStore.wake_submitted(context, &1, now))

      :ok
    else
      _invalid -> {:error, :not_found}
    end
  end

  # Ids under a "guid" key anywhere in the body, also inside a JSON string.
  defp submission_ids(body) when is_map(body) do
    Enum.flat_map(body, fn
      {key, value} when key in ["guid", "document_submission_guid"] and is_binary(value) ->
        [value]

      {_key, value} when is_binary(value) ->
        case Jason.decode(value) do
          {:ok, decoded} when is_map(decoded) -> submission_ids(decoded)
          _other -> []
        end

      {_key, value} when is_map(value) or is_list(value) ->
        submission_ids(value)

      _other ->
        []
    end)
    |> Enum.uniq()
    |> Enum.take(20)
  end

  defp submission_ids(list) when is_list(list), do: Enum.flat_map(list, &submission_ids/1)
  defp submission_ids(_body), do: []

  @doc false
  def token_hash(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  # ── Connection ──────────────────────────────────────────────────────────

  @doc "The connection as shown to staff (never the API key or webhook token)."
  def connection(context) do
    context
    |> EInvoiceStore.get_connection(@network)
    |> public_connection()
  end

  defp public_connection(nil), do: nil

  defp public_connection(connection) do
    connection
    |> Map.take([
      :network,
      :provider,
      :environment,
      :legal_entity_id,
      :status,
      :last_error,
      :updated_at
    ])
    |> Map.merge(%{
      peppol_id:
        PeppolId.format(%{
          scheme: connection.peppol_scheme,
          identifier: connection.peppol_identifier
        }),
      has_api_key: is_binary(connection.api_key),
      has_webhook_token: is_binary(connection.webhook_token_hash)
    })
  end

  @doc """
  Saves the Peppol connection. `test` and `production` go through
  Storecove and need the legal entity id and API key; a saved key is kept
  when none is sent. The business's Peppol id defaults to the `0208`
  enterprise number of its identity. A webhook token is made on the first
  save (or when `rotate_webhook_token` is true) and returned once.
  Journals the change (never the key or token) and wakes the waiting
  documents.
  """
  def save_connection(context, params, actor_id, %DateTime{} = now) do
    before = EInvoiceStore.get_connection(context, @network)
    identity = FiscalStore.get_identity(context)

    with {:ok, attrs} <- validate_connection(before, identity, params) do
      token =
        if is_nil(before) or is_nil(before.webhook_token_hash) or
             params[:rotate_webhook_token] == true,
           do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

      attrs = if token, do: Map.put(attrs, :webhook_token_hash, token_hash(token)), else: attrs

      FiscalStore.transaction(context, fn ->
        with {:ok, saved} <-
               EInvoiceStore.save_connection(
                 context,
                 @network,
                 Map.merge(attrs, %{status: "active", last_error: nil, updated_by_id: actor_id})
               ),
             {:ok, _entry} <-
               Fiscal.append(context, %{
                 event_type: "network_connection_saved",
                 subject_type: "network_connection",
                 subject_id: saved.id,
                 actor_id: actor_id,
                 occurred_at: now,
                 payload: %{
                   network: @network,
                   provider: saved.provider,
                   environment: saved.environment,
                   peppol_id: "#{saved.peppol_scheme}:#{saved.peppol_identifier}",
                   legal_entity_id: saved.legal_entity_id,
                   key_changed: Map.has_key?(attrs, :api_key),
                   webhook_token_changed: not is_nil(token)
                 }
               }) do
          EInvoiceStore.wake_waiting(context, now)
          {:ok, saved |> public_connection() |> Map.put(:webhook_token, token)}
        end
      end)
    end
  end

  defp validate_connection(before, identity, params) do
    environment = params[:environment]
    sandbox? = environment == "sandbox"
    key = clean(params[:api_key])
    stored_key = before && before.api_key
    legal_entity_id = clean(params[:legal_entity_id]) || (before && before.legal_entity_id)

    peppol =
      case clean(params[:peppol_id]) do
        nil -> default_peppol_id(before, identity)
        id -> PeppolId.parse(id)
      end

    errors =
      %{}
      |> add_error(environment not in @environments, :environment, "invalid")
      |> add_error(match?({:error, _}, peppol), :peppol_id, "invalid")
      |> add_error(not sandbox? and is_nil(legal_entity_id), :legal_entity_id, "required")
      |> add_error(not sandbox? and is_nil(key) and is_nil(stored_key), :api_key, "required")
      |> add_error(
        is_binary(legal_entity_id) and String.length(legal_entity_id) > 40,
        :legal_entity_id,
        "too_long"
      )
      |> add_error(is_binary(key) and String.length(key) > 500, :api_key, "too_long")

    if errors == %{} do
      {:ok, peppol_id} = peppol

      {:ok,
       %{
         environment: environment,
         provider: if(sandbox?, do: "sandbox", else: "storecove"),
         peppol_scheme: peppol_id.scheme,
         peppol_identifier: peppol_id.identifier,
         legal_entity_id: if(sandbox?, do: nil, else: legal_entity_id)
       }
       |> then(fn attrs -> if key, do: Map.put(attrs, :api_key, key), else: attrs end)}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  defp default_peppol_id(%{peppol_scheme: scheme, peppol_identifier: identifier}, _identity),
    do: {:ok, %{scheme: scheme, identifier: identifier}}

  defp default_peppol_id(_before, identity) when is_map(identity) do
    case PeppolId.be_number(identity.tax_id || identity.vat_number) do
      nil -> {:error, :invalid_peppol_id}
      number -> {:ok, %{scheme: "0208", identifier: number}}
    end
  end

  defp default_peppol_id(_before, _identity), do: {:error, :invalid_peppol_id}

  defp add_error(errors, true, field, code), do: Map.put(errors, field, [code])
  defp add_error(errors, false, _field, _code), do: errors

  defp clean(nil), do: nil

  defp clean(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp clean(value) when is_integer(value), do: Integer.to_string(value)
  defp clean(_value), do: nil

  defp atom_keys(nil), do: nil

  defp atom_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      pair -> pair
    end)
  end
end
