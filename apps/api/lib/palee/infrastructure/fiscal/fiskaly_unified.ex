defmodule Palee.Infrastructure.Fiscal.FiskalyUnified do
  @moduledoc """
  fiskaly's Unified API (version `2026-06-01`), shared by fiskaly
  E-INVOICE (ADR-250) and fiskaly SIGN FR (ADR-266).

    * Hosts: `https://test.api.fiskaly.com` (TEST) and
      `https://live.api.fiskaly.com` (LIVE); Palee's `test` environment
      uses TEST, `production` uses LIVE. Overridable in config
      (`:palee, :fiskaly_unified, base_urls: %{"test" => ..., "production" => ...}`).
    * Auth: `POST /tokens` `{content: {type: API_KEY, key, secret}}` with
      the key and secret of an API key of the business's `UNIT`
      organization → `content.authentication.bearer`, sent as
      `Authorization: Bearer`.
    * Every request carries `X-Api-Version`; every `POST`/`PATCH` carries
      `X-Idempotency-Key` (a UUID v3 or v4). fiskaly keeps a key's answer
      for 24 hours and replays it for the same method and body; the same
      key with another body is `422`, a key still being processed is
      `409`. Palee derives its keys from its own ids (`idempotency_key/1`),
      so a retry of the same step is a replay, never a second record.
    * A business interaction is two records: an `INTENTION` (operation
      `TRANSACTION`) on a `System`, then a `TRANSACTION` record (operation
      `RECEIPT`, `INVOICE` or `CORRECTION`) linked to it. A record answers
      with `state` (`ACCEPTED`, `REJECTED`, `COMPLETED`, `FAILED`), `mode`
      (`PROCESSING`, `FINISHED`) and `logs` (`[%{severity, message}]`).

  This module also maps a Palee fiscal document to the operation's
  `entries`, `breakdown`, `totals` and `payments` (money as decimal
  strings, VAT codes from the System's own `vat_rates`).

  Spec: https://workspace.fiskaly.com/specs/fiskaly.uapi.e-invoice-be.2026-06-01.yaml
  and https://workspace.fiskaly.com/specs/fiskaly.uapi.sign-fr.2026-06-01.yaml
  (rendered at https://workspace.fiskaly.com/unified-api/api-spec/).
  """

  alias Palee.Infrastructure.Fiscal.Http

  @version "2026-06-01"
  @base_urls %{
    "test" => "https://test.api.fiskaly.com",
    "production" => "https://live.api.fiskaly.com"
  }
  # RFC 4122 URL namespace, for name-based (v3) idempotency keys.
  @namespace <<0x6BA7B811::32, 0x9DAD::16, 0x11D1::16, 0x80B4::16, 0x00C04FD430C8::48>>

  def version, do: @version

  # ── Credentials and token ───────────────────────────────────────────────

  @doc "`:ok` when the connection has a key and a secret."
  def credentials(%{api_key: key, api_secret: secret})
      when is_binary(key) and key != "" and is_binary(secret) and secret != "",
      do: :ok

  def credentials(_connection), do: {:error, {:unauthorized, :credentials_missing}}

  @doc "A bearer token for the connection's API key."
  def token(connection) do
    body = %{content: %{type: "API_KEY", key: connection.api_key, secret: connection.api_secret}}

    case send_request(connection, nil, :post, "/tokens", body, idempotency_key("token")) do
      {:ok, %{"content" => %{"authentication" => %{"bearer" => bearer}}}}
      when is_binary(bearer) ->
        {:ok, bearer}

      {:ok, _other} ->
        {:error, {:unauthorized, :no_token}}

      {:error, {:rejected, _errors}} ->
        {:error, {:unauthorized, :token_refused}}

      {:error, {:not_found, _body}} ->
        {:error, {:unauthorized, :token_refused}}

      # Nothing is written by making a token: safe to try again.
      {:error, {:uncertain, reason}} ->
        {:error, {:transient, reason}}

      error ->
        error
    end
  end

  # ── Requests ────────────────────────────────────────────────────────────

  @doc """
  `{:ok, body}` (the whole JSON answer, `%{"content" => ...}`) or an
  error: `{:rejected, errors}` (400/422), `{:not_found, body}`,
  `{:uncertain, :idempotency_key_reused | :in_progress | reason}`,
  `{:unauthorized, _}`, `{:transient, _}`.

  The last answer is kept in the process (`last_response/0`) for the
  attempt log; the token request is never kept.
  """
  def post(connection, token, path, body, key),
    do: send_request(connection, token, :post, path, body, key)

  def patch(connection, token, path, body, key),
    do: send_request(connection, token, :patch, path, body, key)

  def get(connection, token, path), do: send_request(connection, token, :get, path, nil, nil)

  defp send_request(connection, token, method, path, body, key) do
    headers =
      [{"x-api-version", @version}, {"accept", "application/json"}]
      |> add_header(token && {"authorization", "Bearer " <> token})
      |> add_header(key && {"x-idempotency-key", key})

    [method: method, url: base_url(connection.environment) <> path, headers: headers]
    |> then(fn options -> if body, do: Keyword.put(options, :json, body), else: options end)
    |> Http.request()
    |> case do
      {:ok, response} ->
        unless path == "/tokens",
          do: Process.put(:fiskaly_unified_last, {response.status, response.body})

        interpret(response)

      error ->
        error
    end
  end

  defp add_header(headers, nil), do: headers
  defp add_header(headers, header), do: headers ++ [header]

  defp interpret(%Req.Response{status: 404} = response),
    do: {:error, {:not_found, Http.json(response)}}

  defp interpret(%Req.Response{status: 409}), do: {:error, {:uncertain, :in_progress}}

  defp interpret(response) do
    with {:ok, response} <- Http.classify(response) do
      body = Http.json(response)

      cond do
        response.status in 200..299 ->
          {:ok, body}

        response.status == 422 and idempotency_error?(body) ->
          {:error, {:uncertain, :idempotency_key_reused}}

        response.status in 400..499 ->
          {:error, {:rejected, errors(body, response.status)}}

        true ->
          {:error, {:http, response.status}}
      end
    end
  end

  defp idempotency_error?(body) do
    body
    |> inspect()
    |> String.downcase()
    |> String.contains?("idempoten")
  end

  @doc "The `[%{code, message}]` of an error answer."
  def errors(%{"code" => code} = body, _status) when is_binary(code),
    do: [%{code: code, message: to_string(body["message"] || body["error"] || code)}]

  def errors(_body, status), do: [%{code: to_string(status), message: "Refused by fiskaly"}]

  @doc "A record's error logs as `[%{code, message}]` (`code` is the state)."
  def log_errors(content) do
    state = content["state"] |> to_string() |> String.downcase()

    case Enum.filter(List.wrap(content["logs"]), &(&1["severity"] == "ERROR")) do
      [] -> [%{code: state, message: "fiskaly #{state}"}]
      logs -> Enum.map(logs, &%{code: state, message: to_string(&1["message"])})
    end
  end

  @doc "`{status, body}` of the last answer in this process (never the token's)."
  def take_last_response, do: Process.delete(:fiskaly_unified_last) || {nil, nil}

  @doc "Clears the last answer before a new call."
  def reset, do: Process.delete(:fiskaly_unified_last)

  @doc """
  A UUID v3 (RFC 4122, URL namespace) for `name`: the same name always
  gives the same key, so a repeated step is a replay at fiskaly.
  """
  def idempotency_key(name) do
    <<a::32, b::16, _v::4, c::12, _var::2, d::62>> =
      :crypto.hash(:md5, @namespace <> "palee:" <> name)

    <<a::32, b::16, 3::4, c::12, 2::2, d::62>>
    |> Base.encode16(case: :lower)
    |> then(fn hex ->
      <<p1::binary-8, p2::binary-4, p3::binary-4, p4::binary-4, p5::binary-12>> = hex
      Enum.join([p1, p2, p3, p4, p5], "-")
    end)
  end

  defp base_url(environment) do
    urls =
      :palee
      |> Application.get_env(:fiskaly_unified, [])
      |> Keyword.get(:base_urls, %{})

    urls
    |> Map.get(environment, Map.get(@base_urls, environment, @base_urls["test"]))
    |> String.trim_trailing("/")
  end

  # ── Records ─────────────────────────────────────────────────────────────

  @doc """
  Creates the `INTENTION` and the `TRANSACTION` record for `operation` on
  `system_id`. Keys are derived from `name`, so calling it again with the
  same name within fiskaly's 24 hours replays both answers.
  `{:ok, transaction_content}` or an error.
  """
  def record(connection, token, system_id, operation, name) do
    intention = %{
      content: %{type: "INTENTION", system: %{id: system_id}, operation: %{type: "TRANSACTION"}}
    }

    with {:ok, %{"content" => %{"id" => intention_id}}} <-
           post(connection, token, "/records", intention, idempotency_key(name <> ":intention")),
         {:ok, %{"content" => content}} <-
           post(
             connection,
             token,
             "/records",
             %{
               content: %{type: "TRANSACTION", record: %{id: intention_id}, operation: operation}
             },
             idempotency_key(name <> ":transaction")
           ) do
      {:ok, content}
    else
      {:ok, _unexpected} -> {:error, {:uncertain, :unexpected_answer}}
      error -> error
    end
  end

  @doc "The System's VAT rate codes by percentage (`\"21.00\" => \"STANDARD\"`) and exemptions."
  def vat_table(connection, token, system_id) do
    case get(connection, token, "/systems/" <> URI.encode_www_form(system_id)) do
      {:ok, %{"content" => system}} ->
        rates =
          system
          |> Map.get("vat_rates", [])
          |> Enum.reject(&(&1["historic"] == true))
          |> Map.new(&{normalize_percent(&1["percentage"]), &1["code"]})

        exemptions = system |> Map.get("vat_exemptions", []) |> Enum.map(& &1["code"])
        {:ok, %{rates: rates, exemptions: exemptions}}

      {:ok, _other} ->
        {:ok, %{rates: %{}, exemptions: []}}

      {:error, {:not_found, _body}} ->
        {:error, {:rejected, [%{code: "system_not_found", message: "fiskaly System not found"}]}}

      {:error, {:uncertain, reason}} ->
        {:error, {:transient, reason}}

      error ->
        error
    end
  end

  defp normalize_percent(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal |> Decimal.round(2) |> Decimal.to_string(:normal)
      _other -> value
    end
  end

  defp normalize_percent(value) when is_number(value), do: normalize_percent(to_string(value))
  defp normalize_percent(_value), do: nil

  # ── Document mapping ────────────────────────────────────────────────────

  @doc """
  The `entries`, `breakdown`, `totals` and `payments` of a fiscal
  document, with VAT codes from `vat` (`vat_table/3`). Lines are `SALE`,
  or `RETURN` with `returns: true` (credit notes); amounts are positive.
  `{:ok, map}` or `{:error, {:rejected, errors}}` when a rate or an
  exemption has no code at the System.
  """
  def operation_body(document, vat, opts \\ []) do
    returns? = Keyword.get(opts, :returns, false)
    lines = document.lines |> Enum.sort_by(& &1.position)

    with {:ok, entries} <- map_all(lines, &entry(&1, vat, returns?)),
         {:ok, breakdown} <- map_all(document.tax_breakdown, &breakdown_entry(&1, vat)) do
      {:ok,
       %{
         entries: entries,
         breakdown: breakdown,
         totals: %{
           vat: %{
             amount: amount(document.tax_cents),
             exclusive: amount(document.net_cents),
             inclusive: amount(document.gross_cents)
           }
         },
         payments: [payment(document)]
       }}
    end
  end

  defp map_all(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, mapped} -> {:cont, {:ok, [mapped | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, mapped} -> {:ok, Enum.reverse(mapped)}
      error -> error
    end
  end

  defp entry(line, vat, returns?) do
    quantity = max(abs(line.quantity), 1)

    with {:ok, line_vat} <- entry_vat(line, vat) do
      {:ok,
       %{
         type: if(returns?, do: "RETURN", else: "SALE"),
         data: %{
           type: "ITEM",
           text: line.description |> to_string() |> String.slice(0, 256),
           unit: %{
             quantity: Integer.to_string(quantity),
             price: %{
               exclusive: unit_amount(line.net_cents, quantity),
               inclusive: unit_amount(line.gross_cents, quantity)
             }
           },
           value: %{base: amount(line.net_cents)},
           vat: line_vat
         },
         details: %{concept: concept(line), number: Integer.to_string(line.position)}
       }}
    end
  end

  defp concept(%{source_type: type}) when type in ["product", "shop_item", "inventory_item"],
    do: "GOOD"

  defp concept(_line), do: "SERVICE"

  defp entry_vat(line, vat) do
    case vat_kind(line.tax_category, line.rate_bp, vat) do
      {:rate, code} ->
        {:ok,
         %{
           type: "VAT_RATE",
           code: code,
           percentage: percent(line.rate_bp),
           amount: amount(line.tax_cents),
           exclusive: amount(line.net_cents),
           inclusive: amount(line.gross_cents)
         }}

      {:exemption, code} ->
        {:ok,
         %{type: "VAT_EXEMPTION", code: code}
         |> put_reason(line.exemption_reason)}

      error ->
        error
    end
  end

  defp put_reason(map, reason) when is_binary(reason) and reason != "",
    do: Map.put(map, :reason, String.slice(reason, 0, 128))

  defp put_reason(map, _reason), do: map

  defp breakdown_entry(group, vat) do
    group = atom_keys(group)

    case vat_kind(group[:tax_category], group.rate_bp, vat) do
      {:rate, code} ->
        {:ok,
         %{
           type: "VAT_RATE",
           code: code,
           percentage: percent(group.rate_bp),
           amount: amount(group.tax_cents),
           exclusive: amount(group.net_cents),
           inclusive: amount(group.net_cents + group.tax_cents)
         }}

      {:exemption, code} ->
        {:ok, %{type: "VAT_EXEMPTION", code: code, exclusive: amount(group.net_cents)}}

      error ->
        error
    end
  end

  # A rate is looked up by its percentage among the System's rates; a 0 %
  # line without a 0 % rate, or an exempt line, needs an exemption code:
  # the only one the System lists, else it is refused before sending.
  defp vat_kind("exempt", _rate_bp, vat), do: exemption(vat)

  defp vat_kind(_category, rate_bp, vat) do
    case Map.fetch(vat.rates, percent(rate_bp)) do
      {:ok, code} -> {:rate, code}
      :error when rate_bp == 0 -> exemption(vat)
      :error -> unmapped("vat_rate_unmapped", "No fiskaly VAT code for #{percent(rate_bp)} %")
    end
  end

  defp exemption(%{exemptions: [code]}), do: {:exemption, code}

  defp exemption(_vat),
    do: unmapped("vat_exemption_unmapped", "No single fiskaly VAT exemption code for this System")

  defp unmapped(code, message), do: {:error, {:rejected, [%{code: code, message: message}]}}

  defp payment(%{payment_method: "cash"} = document),
    do: %{type: "CASH", details: %{amount: amount(document.gross_cents)}}

  # A CARD payment needs the masked card number and kind, which Palee does
  # not keep: card and online payments are ONLINE with a name.
  defp payment(%{payment_method: method} = document) when method in ["card", "online"],
    do: %{
      type: "ONLINE",
      name: if(method == "card", do: "Card", else: "Online"),
      details: %{amount: amount(document.gross_cents), currency: document.currency}
    }

  defp payment(document),
    do: %{
      type: "OUTSTANDING",
      concept: "INVOICE",
      details: %{
        amount: amount(document.gross_cents),
        currency: document.currency,
        date: Date.to_iso8601(document.issue_date)
      }
    }

  @doc "A document number as fiskaly accepts it (`^[0-9A-Z_/\\-.]{1,20}$`), or nil."
  def document_number(number) when is_binary(number) do
    upper = String.upcase(number)
    if Regex.match?(~r/^[0-9A-Z_\/\-\.]{1,20}$/, upper), do: upper
  end

  def document_number(_number), do: nil

  @doc "An RFC 3339 time with offset, 25 characters (`2027-02-08T10:00:00+00:00`)."
  def timestamp(%DateTime{} = time) do
    time
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
    |> String.replace_suffix("Z", "+00:00")
  end

  def timestamp(_time), do: nil

  @doc "Cents as a positive decimal string (`1234` → `\"12.34\"`)."
  def amount(cents) when is_integer(cents) do
    cents = abs(cents)

    Integer.to_string(div(cents, 100)) <>
      "." <> String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")
  end

  def amount(_cents), do: "0.00"

  # Up to 8 decimals (Decimal12p8), trailing zeros kept to two.
  defp unit_amount(cents, quantity) do
    cents
    |> abs()
    |> Decimal.new()
    |> Decimal.div(Decimal.new(quantity * 100))
    |> Decimal.round(8)
    |> Decimal.normalize()
    |> then(fn value ->
      text = Decimal.to_string(value, :normal)

      case String.split(text, ".") do
        [whole] -> whole <> ".00"
        [whole, fraction] -> whole <> "." <> String.pad_trailing(fraction, 2, "0")
      end
    end)
  end

  @doc "Basis points as a percentage with two decimals (`2100` → `\"21.00\"`)."
  def percent(bp) when is_integer(bp),
    do:
      Integer.to_string(div(bp, 100)) <>
        "." <> String.pad_leading(Integer.to_string(rem(bp, 100)), 2, "0")

  defp atom_keys(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      pair -> pair
    end)
  end
end
