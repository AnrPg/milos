defmodule Palee.Infrastructure.Fiscal.MyDataGateway do
  @moduledoc """
  AADE myDATA REST API, ERP channel (ADR-243): `POST /SendInvoices` with
  the business's own myDATA user and subscription key.

  Environments: `test` → AADE's development API, `production` → the live
  API. Base URLs come from config (`:palee, :mydata`) so a proxy or a
  test plug can stand in; requests honour the outbound proxy like the
  other adapters (`req_options`).

  Results (see `Fiscal.Ports.AuthorityGateway`): a `Success` response with
  an `invoiceMark` is accepted; `ValidationError`/`XMLSyntaxError` are
  rejections; HTTP 401/403 means the credentials were refused; everything
  else (timeouts, 5xx, 429, `TechnicalError`) is transient and retried.
  """

  @behaviour Palee.Fiscal.Ports.AuthorityGateway

  alias Palee.Infrastructure.Fiscal.MyData.XmlCodec

  @base_urls %{
    "test" => "https://mydataapidev.aade.gr",
    "production" => "https://mydatapi.aade.gr/myDATA"
  }
  @max_logged_body 65_536

  @impl true
  def submit(connection, invoice) do
    body = XmlCodec.invoices_doc([invoice])

    with {:ok, base_url} <- base_url(connection.environment),
         :ok <- credentials(connection) do
      config = Application.get_env(:palee, :mydata, [])

      [
        url: base_url <> "/SendInvoices",
        body: body,
        headers: [
          {"aade-user-id", connection.user_id},
          {"ocp-apim-subscription-key", connection.subscription_key},
          {"content-type", "application/xml; charset=utf-8"}
        ],
        receive_timeout: Keyword.get(config, :receive_timeout, 30_000),
        retry: false,
        decode_body: false
      ]
      |> Keyword.merge(Keyword.get(config, :req_options, []))
      |> Req.post()
      |> interpret(body)
    else
      {:error, reason} -> {{:error, reason}, wire(body, nil, nil)}
    end
  end

  # A MARK no document will reach for years: the answer lists nothing.
  @check_mark "999999999999999"

  @doc """
  «Δοκιμή σύνδεσης» (ADR-273): `GET /RequestTransmittedDocs` for documents
  after a MARK no document has, with the business's user and key. Nothing
  is reported; a 200 means AADE took the credentials, 401/403 that it
  refused them. The key never leaves the headers.
  """
  @impl true
  def check(connection) do
    with {:ok, base_url} <- base_url(connection.environment),
         :ok <- credentials(connection) do
      config = Application.get_env(:palee, :mydata, [])

      [
        url: base_url <> "/RequestTransmittedDocs",
        params: [mark: @check_mark],
        headers: [
          {"aade-user-id", connection.user_id},
          {"ocp-apim-subscription-key", connection.subscription_key}
        ],
        receive_timeout: Keyword.get(config, :check_timeout, 15_000),
        retry: false,
        decode_body: false
      ]
      |> Keyword.merge(Keyword.get(config, :req_options, []))
      |> Req.get()
      |> case do
        {:ok, %Req.Response{status: 200}} ->
          {:ok, %{}}

        {:ok, %Req.Response{status: status}} when status in [401, 403] ->
          {:error, {:unauthorized, {:http, status}}}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:http, status}}

        {:error, exception} ->
          {:error, {:network, Exception.message(exception)}}
      end
    end
  end

  defp base_url(environment) do
    urls =
      Map.merge(
        @base_urls,
        :palee |> Application.get_env(:mydata, []) |> Keyword.get(:base_urls, %{})
      )

    case Map.fetch(urls, environment) do
      {:ok, url} -> {:ok, String.trim_trailing(url, "/")}
      :error -> {:error, {:unauthorized, :unknown_environment}}
    end
  end

  defp credentials(%{user_id: user, subscription_key: key})
       when is_binary(user) and user != "" and is_binary(key) and key != "",
       do: :ok

  defp credentials(_connection), do: {:error, {:unauthorized, :credentials_missing}}

  defp interpret({:ok, %Req.Response{status: status, body: response}}, body)
       when status in [401, 403] do
    {{:error, {:unauthorized, {:http, status}}}, wire(body, status, response)}
  end

  defp interpret({:ok, %Req.Response{status: status, body: response}}, body)
       when status in [200, 400] do
    result =
      case XmlCodec.parse_response(to_string(response)) do
        {:ok, [%{status: "Success", mark: mark} = first | _rest]} when is_binary(mark) ->
          {:ok, Map.take(first, [:mark, :uid, :authentication_code, :qr_url])}

        {:ok, [%{status: code, errors: errors} | _rest]}
        when code in ["ValidationError", "XMLSyntaxError"] ->
          {:error, {:rejected, errors}}

        {:ok, [%{status: other, errors: errors} | _rest]} ->
          {:error, {:technical, other, errors}}

        {:ok, []} ->
          {:error, :empty_response}

        {:error, reason} ->
          {:error, reason}
      end

    {result, wire(body, status, response)}
  end

  defp interpret({:ok, %Req.Response{status: status, body: response}}, body),
    do: {{:error, {:http, status}}, wire(body, status, response)}

  defp interpret({:error, exception}, body),
    do: {{:error, {:network, Exception.message(exception)}}, wire(body, nil, nil)}

  defp wire(request, status, response) do
    %{
      request_body: request,
      response_status: status,
      response_body: response && response |> to_string() |> binary_part_safe(@max_logged_body)
    }
  end

  defp binary_part_safe(text, max) when byte_size(text) <= max, do: text
  defp binary_part_safe(text, max), do: String.slice(text, 0, max)
end
