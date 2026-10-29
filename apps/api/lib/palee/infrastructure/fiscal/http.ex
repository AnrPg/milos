defmodule Palee.Infrastructure.Fiscal.Http do
  @moduledoc """
  The HTTP call shared by the e-invoicing and cash-register adapters
  (ADR-250, ADR-251): honours the outbound proxy and test plugs
  (`config :palee, :fiscal_http, req_options: [...]`), never retries by
  itself (the outbox does), and sorts failures into what the ports
  understand.

  A request that may have reached the provider (a timeout, a dropped
  connection) is `{:uncertain, reason}`; one that surely did not (refused
  connection, unknown host) is `{:transient, reason}`.

  Logged bodies are capped and never contain credentials: callers pass
  only the document part of a request to the attempt log.
  """

  @safe_reasons [:econnrefused, :nxdomain, :ehostunreach, :enetunreach, :eaddrnotavail]
  @max_logged_body 65_536

  def request(options) do
    config = Application.get_env(:palee, :fiscal_http, [])

    options
    |> Keyword.merge(
      receive_timeout: Keyword.get(config, :receive_timeout, 30_000),
      retry: false
    )
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.request()
    |> case do
      {:ok, %Req.Response{} = response} ->
        {:ok, response}

      {:error, %Req.TransportError{reason: reason}} when reason in @safe_reasons ->
        {:error, {:transient, reason}}

      {:error, exception} ->
        {:error, {:uncertain, Exception.message(exception)}}
    end
  end

  @doc "Common status handling: 401/403 credentials, 429/5xx transient."
  def classify(%Req.Response{status: status}) when status in [401, 403],
    do: {:error, {:unauthorized, {:http, status}}}

  def classify(%Req.Response{status: status}) when status == 429 or status >= 500,
    do: {:error, {:transient, {:http, status}}}

  def classify(%Req.Response{} = response), do: {:ok, response}

  @doc "What goes into the attempt log."
  def wire(request_body, status, response_body) do
    %{
      request_body: request_body && cap(request_body),
      response_status: status,
      response_body: response_body && response_body |> body_text() |> cap()
    }
  end

  defp body_text(body) when is_binary(body), do: body
  defp body_text(body), do: Jason.encode!(body)

  defp cap(text) when byte_size(text) <= @max_logged_body, do: text
  defp cap(text), do: String.slice(text, 0, @max_logged_body)

  @doc "A JSON body as a map, whatever Req made of it."
  def json(%Req.Response{body: body}) when is_map(body) or is_list(body), do: body

  def json(%Req.Response{body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      _error -> %{}
    end
  end

  def json(_response), do: %{}
end
