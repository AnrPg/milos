defmodule Palee.Infrastructure.Fiscal.StorecoveNetwork do
  @moduledoc """
  Storecove, a Peppol access point as a service (ADR-250).

  The business has a Storecove legal entity (with its Peppol identifier
  registered on it) and an API key. Palee generates the UBL itself and
  hands it over as `rawDocumentData` with `parseStrategy: "ubl"`, so what
  is sent is exactly the document Palee validated:

      POST {base}/document_submissions
      Authorization: Bearer <api key>
      {"legalEntityId": 123,
       "idempotencyGuid": "<guid>",
       "routing": {"eIdentifiers": [{"scheme": "BE:EN", "id": "0123456789"}]},
       "document": {"documentType": "invoice",
                    "rawDocumentData": {"document": "<base64 UBL>",
                                        "parse": true, "parseStrategy": "ubl"}}}

  The answer is the submission's `guid`. Delivery is read from the
  submission's evidence (`GET {base}/document_submissions/{guid}/evidence/sending`):
  evidence means the receiver's access point acknowledged the document;
  404 means it is still on its way. Storecove's webhooks only make the
  next poll due (ADR-250).

  Storecove refuses a second submission with the same `idempotencyGuid`
  (HTTP 422); Palee reads that as "the first one may have arrived"
  (`{:uncertain, :duplicate_idempotency_guid}`), never as a rejection.

  Base URL and paths come from config (`:palee, :storecove`) so a test plug
  or Storecove's sandbox account can stand in. Written from Storecove's
  public API documentation (https://www.storecove.com/docs/); to be
  confirmed against a Storecove sandbox account before the first live box.
  """

  @behaviour Palee.Fiscal.Ports.EInvoiceNetwork

  alias Palee.Infrastructure.Fiscal.Http
  alias Palee.Infrastructure.Fiscal.Peppol.UblWriter

  @base_url "https://api.storecove.com/api/v2"

  # Peppol ICD scheme → Storecove's routing scheme name.
  @schemes %{
    "0208" => "BE:EN",
    "9925" => "BE:VAT",
    "0088" => "GLN",
    "0106" => "NL:KVK",
    "0190" => "NL:OINO",
    "9930" => "DE:VAT",
    "0204" => "DE:LWID",
    "9914" => "AT:VAT",
    "9915" => "AT:GOV",
    "0007" => "SE:ORGNR",
    "0192" => "NO:ORG",
    "0184" => "DK:DIGST",
    "0009" => "FR:SIRET",
    "0225" => "FR:SIRENE",
    "0060" => "DUNS",
    "0151" => "AU:ABN"
  }

  @doc "Storecove's routing scheme for a Peppol ICD scheme."
  def routing_scheme(icd), do: Map.get(@schemes, icd, icd)

  @impl true
  def submit(connection, %{ubl: ubl, idempotency_guid: guid, recipient: recipient}) do
    xml = UblWriter.write(ubl)

    with :ok <- credentials(connection),
         {:ok, legal_entity_id} <- legal_entity_id(connection) do
      payload = %{
        legalEntityId: legal_entity_id,
        idempotencyGuid: guid,
        routing: %{
          eIdentifiers: [%{scheme: routing_scheme(recipient.scheme), id: recipient.identifier}],
          emails: []
        },
        document: %{
          documentType: "invoice",
          rawDocumentData: %{document: Base.encode64(xml), parse: true, parseStrategy: "ubl"}
        }
      }

      [
        method: :post,
        url: base_url() <> "/document_submissions",
        json: payload,
        headers: headers(connection)
      ]
      |> Http.request()
      |> interpret_submit(xml)
    else
      {:error, reason} -> {{:error, reason}, Http.wire(xml, nil, nil)}
    end
  end

  defp interpret_submit({:ok, response}, xml) do
    result =
      with {:ok, response} <- Http.classify(response) do
        body = Http.json(response)

        cond do
          response.status in 200..299 and is_binary(body["guid"]) ->
            {:ok, %{submission_id: body["guid"]}}

          response.status == 422 and duplicate_guid?(body) ->
            {:error, {:uncertain, :duplicate_idempotency_guid}}

          response.status in 400..499 ->
            {:error, {:rejected, errors(body, response.status)}}

          true ->
            {:error, {:http, response.status}}
        end
      end

    {result, Http.wire(xml, response.status, response.body)}
  end

  defp interpret_submit({:error, reason}, xml), do: {{:error, reason}, Http.wire(xml, nil, nil)}

  @impl true
  def status(connection, submission_id) do
    with :ok <- credentials(connection) do
      [
        method: :get,
        url:
          base_url() <>
            "/document_submissions/" <> URI.encode_www_form(submission_id) <> "/evidence/sending",
        headers: headers(connection)
      ]
      |> Http.request()
      |> case do
        {:ok, %Req.Response{status: 404} = response} ->
          {{:ok, :in_progress}, Http.wire(nil, 404, response.body)}

        {:ok, response} ->
          result =
            with {:ok, response} <- Http.classify(response) do
              body = Http.json(response)

              cond do
                response.status in 200..299 and failed?(body) ->
                  {:ok, {:failed, errors(body, response.status)}}

                response.status in 200..299 and body != %{} ->
                  {:ok, :delivered}

                response.status in 200..299 ->
                  {:ok, :in_progress}

                true ->
                  {:error, {:http, response.status}}
              end
            end

          {result, Http.wire(nil, response.status, response.body)}

        # A read is always safe to repeat.
        {:error, {:uncertain, reason}} ->
          {{:error, {:transient, reason}}, Http.wire(nil, nil, nil)}

        {:error, reason} ->
          {{:error, reason}, Http.wire(nil, nil, nil)}
      end
    else
      {:error, reason} -> {{:error, reason}, Http.wire(nil, nil, nil)}
    end
  end

  defp failed?(body) when is_map(body),
    do: body["status"] in ["failed", "error"] or body["transmission_result"] == "failed"

  defp failed?(_body), do: false

  defp duplicate_guid?(body) do
    body
    |> inspect()
    |> String.downcase()
    |> String.contains?("idempotency")
  end

  defp errors(body, status) when is_map(body) do
    case body["errors"] do
      [_ | _] = errors ->
        Enum.map(errors, fn
          %{} = error ->
            %{
              code: to_string(error["source"] || error["code"] || status),
              message: to_string(error["details"] || error["message"] || inspect(error))
            }

          other ->
            %{code: to_string(status), message: to_string(other)}
        end)

      _none ->
        [%{code: to_string(status), message: body["message"] || "Refused by Storecove"}]
    end
  end

  defp errors(body, status) when is_list(body), do: errors(%{"errors" => body}, status)
  defp errors(_body, status), do: [%{code: to_string(status), message: "Refused by Storecove"}]

  defp credentials(%{api_key: key}) when is_binary(key) and key != "", do: :ok
  defp credentials(_connection), do: {:error, {:unauthorized, :credentials_missing}}

  defp legal_entity_id(%{legal_entity_id: id}) when is_binary(id) do
    case Integer.parse(id) do
      {number, ""} -> {:ok, number}
      _other -> {:ok, id}
    end
  end

  defp legal_entity_id(_connection), do: {:error, {:unauthorized, :legal_entity_missing}}

  defp headers(connection) do
    [
      {"authorization", "Bearer " <> connection.api_key},
      {"accept", "application/json"}
    ]
  end

  defp base_url do
    :palee
    |> Application.get_env(:storecove, [])
    |> Keyword.get(:base_url, @base_url)
    |> String.trim_trailing("/")
  end
end
