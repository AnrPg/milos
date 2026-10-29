defmodule Palee.Infrastructure.Payments.Http do
  @moduledoc """
  The HTTP call shared by the payment adapters (ADR-246): honours the
  outbound proxy and test plugs (`config :palee, :payments_http,
  req_options: [...]`), never retries by itself (the outbox does), and
  sorts failures into what the port understands.

  A request that may have reached the provider (a timeout, a dropped
  connection) is `{:uncertain, reason}`: without an idempotency key the
  caller must not simply send it again.
  """

  @safe_reasons [:econnrefused, :nxdomain, :ehostunreach, :enetunreach, :eaddrnotavail]

  def request(options) do
    config = Application.get_env(:palee, :payments_http, [])

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

  @doc "A card's last 4 digits from a masked number."
  def last4(number) when is_binary(number) do
    digits = String.replace(number, ~r/\D/, "")
    if byte_size(digits) >= 4, do: binary_part(digits, byte_size(digits) - 4, 4)
  end

  def last4(_number), do: nil

  @doc "Cents from a decimal amount as a provider writes it (10.5 → 1050)."
  def cents(amount) when is_integer(amount), do: amount * 100
  def cents(amount) when is_float(amount), do: amount |> Decimal.from_float() |> to_cents()

  def cents(amount) when is_binary(amount) do
    case Decimal.parse(amount) do
      {decimal, ""} -> to_cents(decimal)
      _other -> nil
    end
  end

  def cents(_amount), do: nil

  defp to_cents(decimal),
    do: decimal |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()

  @iso_numeric %{"978" => "EUR", "826" => "GBP", "840" => "USD", "756" => "CHF"}

  def currency_from_numeric(code) when is_integer(code),
    do: currency_from_numeric(Integer.to_string(code))

  def currency_from_numeric(code) when is_binary(code), do: Map.get(@iso_numeric, code, code)
  def currency_from_numeric(_code), do: nil

  def header(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(key) == name, do: value
    end)
  end
end
