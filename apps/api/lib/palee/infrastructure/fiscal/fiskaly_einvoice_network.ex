defmodule Palee.Infrastructure.Fiscal.FiskalyEInvoiceNetwork do
  @moduledoc """
  fiskaly E-INVOICE, Palee's Peppol access point (ADR-250, update
  2026-10-29). fiskaly is the single fiscal vendor outside Greece: the
  same fiskaly account signs German and Austrian till receipts (ADR-251)
  and French ones (ADR-266).

  fiskaly builds the e-invoice itself (Peppol BIS 3.0 in Belgium,
  XRechnung over Peppol in Germany) from the EN 16931 fields it is given
  as JSON; it does not take a UBL file. Palee still builds and validates
  its own UBL first (`Domain.UblInvoice`), so a document Palee could not
  send as BIS 3.0 never reaches fiskaly, and maps the same document to
  fiskaly's fields:

      POST /records {content: {type: INTENTION, system: {id}, operation: {type: TRANSACTION}}}
      POST /records {content: {type: TRANSACTION, record: {id: intention},
                     operation: {type: INVOICE, document, entries, recipients,
                                 payments, breakdown, totals}}}

  A credit note is `operation: {type: CORRECTION, record: {id: <the
  invoice's record>}, reason, data: {type: INVOICE, ... RETURN entries}}`.

  The connection's `legal_entity_id` is the business's fiskaly
  `E_INVOICE_SERVICE` System id (registered on Peppol, proof of ownership
  done, in the fiskaly HUB); the key and secret are those of an API key of
  the business's fiskaly `UNIT`. The submission id is the TRANSACTION
  record's id.

  Delivery (`status/2`): the TRANSACTION record (`GET /records/{id}`) is
  `REJECTED` or `FAILED` when fiskaly refused it; once accepted it links
  (`used_in`) to an `E_INVOICE::TRANSMISSION` record, whose `COMPLETED` +
  `FINISHED` means the Peppol transmission succeeded and `FAILED` /
  `REJECTED` that it did not. fiskaly sends no webhooks: Palee polls.

  Idempotency: the `X-Idempotency-Key`s are UUID v3 derived from the
  submission's GUID, so a staff retry of an uncertain submission within
  fiskaly's 24-hour window replays the first answer instead of sending a
  second invoice; the same key with a different body (`422`) or still
  being processed (`409`) is uncertain, never resent by itself.

  Written from fiskaly's public spec (see `FiskalyUnified`); to be
  confirmed against a fiskaly TEST account before the first live box.
  """

  @behaviour Palee.Fiscal.Ports.EInvoiceNetwork

  alias Palee.Infrastructure.Fiscal.{FiskalyUnified, Http}

  @impl true
  def submit(connection, submission) do
    FiskalyUnified.reset()

    result =
      with :ok <- FiskalyUnified.credentials(connection),
           {:ok, system_id} <- system_id(connection),
           {:ok, token} <- FiskalyUnified.token(connection),
           {:ok, vat} <- FiskalyUnified.vat_table(connection, token, system_id),
           {:ok, operation} <- operation(submission, vat) do
        Process.put(:fiskaly_einvoice_request, Jason.encode!(operation))

        connection
        |> FiskalyUnified.record(token, system_id, operation, "einvoice:" <> submission.idempotency_guid)
        |> submitted()
      end

    request = Process.delete(:fiskaly_einvoice_request)
    {status, body} = FiskalyUnified.take_last_response()
    {normalize(result), Http.wire(request, status, body)}
  end

  defp submitted({:ok, %{"id" => id, "state" => state} = content})
       when state in ["REJECTED", "FAILED"] and is_binary(id),
       do: {:error, {:rejected, FiskalyUnified.log_errors(content)}}

  defp submitted({:ok, %{"id" => id}}) when is_binary(id), do: {:ok, %{submission_id: id}}
  defp submitted({:ok, _content}), do: {:error, {:uncertain, :record_id_missing}}
  defp submitted(error), do: error

  # A 404 while sending means a System or record fiskaly does not know.
  defp normalize({:error, {:not_found, _body}}),
    do: {:error, {:rejected, [%{code: "not_found", message: "Unknown at fiskaly"}]}}

  defp normalize(result), do: result

  defp operation(%{document: document} = submission, vat) do
    with {:ok, number} <- number(document),
         {:ok, recipient} <- recipient(document, submission.recipient),
         {:ok, body} <-
           FiskalyUnified.operation_body(document, vat,
             returns: document.kind == "credit_note"
           ) do
      invoice =
        body
        |> Map.merge(%{
          type: "INVOICE",
          document: invoice_document(document, number),
          recipients: [recipient]
        })

      case document.kind do
        "credit_note" -> correction(invoice, submission[:original], document)
        _invoice -> {:ok, invoice}
      end
    end
  end

  defp operation(_submission, _vat),
    do: {:error, {:rejected, [%{code: "document_missing", message: "palee"}]}}

  defp correction(invoice, %{submission_id: original_id}, document)
       when is_binary(original_id) do
    {:ok,
     %{
       type: "CORRECTION",
       record: %{id: original_id},
       reason: String.slice("Credit note #{document.number}", 0, 128),
       data: invoice
     }}
  end

  defp correction(_invoice, _original, _document),
    do:
      {:error,
       {:rejected,
        [%{code: "original_not_sent", message: "The corrected invoice was not sent via fiskaly"}]}}

  defp invoice_document(document, number) do
    %{
      number: number,
      issued_at: FiskalyUnified.timestamp(document.issued_at),
      operation_date: Date.to_iso8601(document.issue_date),
      references: %{buyer: buyer_reference(document)}
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp buyer_reference(%{buyer: buyer, number: number}) do
    case buyer && (buyer[:reference] || buyer["reference"]) do
      reference when is_binary(reference) and reference != "" -> String.slice(reference, 0, 256)
      _none -> number
    end
  end

  defp number(document) do
    case FiskalyUnified.document_number(document.number) do
      nil ->
        {:error,
         {:rejected,
          [%{code: "document_number_format", message: "fiskaly needs [0-9A-Z_/-.]{1,20}"}]}}

      number ->
        {:ok, number}
    end
  end

  defp recipient(document, peppol) do
    buyer = atom_keys(document.buyer || %{})

    {:ok,
     %{
       type: "BUSINESS",
       name: (buyer[:name] || "-") |> to_string() |> String.slice(0, 128),
       address: %{
         line: %{
           type: "STREET_NUMBER",
           street: present(buyer[:street], "-"),
           number: present(buyer[:building_number], "-")
         },
         code: present(buyer[:postal_code], "-"),
         city: present(buyer[:city], "-"),
         country: buyer[:country_code] || document.country_code
       },
       identification: identification(buyer),
       invoicing: %{type: "PEPPOL", identifier: "#{peppol.scheme}:#{peppol.identifier}"}
     }}
  end

  defp identification(%{vat_number: vat}) when is_binary(vat) and vat != "",
    do: %{type: "VAT", number: vat |> String.upcase() |> String.replace(~r/[\s.\-]/, "")}

  defp identification(%{tax_id: tax_id}) when is_binary(tax_id) and tax_id != "",
    do: %{type: "TAX", number: tax_id}

  defp identification(_buyer), do: %{type: "OTHER", number: "-"}

  defp present(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> default
      text -> String.slice(text, 0, 128)
    end
  end

  defp present(_value, default), do: default

  @impl true
  def status(connection, submission_id) do
    FiskalyUnified.reset()

    result =
      with :ok <- FiskalyUnified.credentials(connection),
           {:ok, token} <- FiskalyUnified.token(connection),
           {:ok, %{"content" => record}} <-
             FiskalyUnified.get(connection, token, "/records/" <> encode(submission_id)) do
        delivery(connection, token, record)
      end

    {status, body} = FiskalyUnified.take_last_response()
    {read_result(result), Http.wire(nil, status, body)}
  end

  defp delivery(_connection, _token, %{"state" => state} = record)
       when state in ["REJECTED", "FAILED"],
       do: {:ok, {:failed, FiskalyUnified.log_errors(record)}}

  defp delivery(connection, token, %{"used_in" => %{"id" => transmission_id}})
       when is_binary(transmission_id) do
    case FiskalyUnified.get(connection, token, "/records/" <> encode(transmission_id)) do
      {:ok, %{"content" => %{"state" => "COMPLETED", "mode" => "FINISHED"}}} ->
        {:ok, :delivered}

      {:ok, %{"content" => %{"state" => state} = transmission}}
      when state in ["REJECTED", "FAILED"] ->
        {:ok, {:failed, FiskalyUnified.log_errors(transmission)}}

      {:ok, _processing} ->
        {:ok, :in_progress}

      error ->
        error
    end
  end

  defp delivery(_connection, _token, _record), do: {:ok, :in_progress}

  # A read is always safe to repeat.
  defp read_result({:error, {:uncertain, reason}}), do: {:error, {:transient, reason}}

  defp read_result({:error, {:not_found, _body}}),
    do: {:ok, {:failed, [%{code: "not_found", message: "fiskaly does not know this record"}]}}

  defp read_result({:ok, state} = result)
       when state in [:delivered, :in_progress] or
              (is_tuple(state) and elem(state, 0) == :failed),
       do: result

  defp read_result({:ok, _unexpected}), do: {:ok, :in_progress}
  defp read_result(error), do: error

  defp system_id(%{legal_entity_id: id}) when is_binary(id) and id != "", do: {:ok, id}
  defp system_id(_connection), do: {:error, {:unauthorized, :system_missing}}

  defp encode(id), do: URI.encode_www_form(id)

  defp atom_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      pair -> pair
    end)
  end
end
