defmodule Palee.Infrastructure.Fiscal.FiskalySignAt do
  @moduledoc """
  fiskaly SIGN AT, a cloud signature creation unit for the RKSV
  (ADR-251).

    * Auth: `POST /api/v1/auth` with the API key and secret → bearer token.
    * Provisioning (`provision/2`): `PUT /signature-creation-unit/{scu_id}`
      (`legal_entity_id`, `legal_entity_name`) → `PATCH {state:
      INITIALIZED}` → `PUT /cash-register/{cash_register_id}`
      (`description`) → `PATCH {state: REGISTERED}` (reported to
      FinanzOnline, which needs the business's FinanzOnline access stored
      at fiskaly) → `PATCH {state: INITIALIZED}`: fiskaly signs the start
      receipt (Startbeleg, a null receipt), which Palee reads back as
      receipt number 1.
    * Signing (`sign/2`): `PUT /cash-register/{id}/receipt/{receipt_id}`
      with `receipt_type: NORMAL` and the `standard_v1` amounts; a null
      receipt (Nullbeleg) has zero amounts. The API is idempotent per
      receipt id. The answer carries the receipt number, the signing time,
      the cash register serial number and the machine-readable code
      (`qr_code_data`); when fiskaly's signature creation unit is out its
      `hints` say "Sicherheitseinrichtung ausgefallen", and the receipt is
      recorded as such (fiskaly clears the fault with its own receipt).
    * Read-back (`lookup/2`): `GET /cash-register/{id}/receipt/{receipt_id}`.

  Monthly and yearly closing receipts and their FinanzOnline checks are
  made by fiskaly SIGN AT itself. Base URL from config (`:palee,
  :fiskaly_sign_at, base_url:`). API: https://workspace.fiskaly.com/api/rksv/v1/.
  Written from fiskaly's public documentation; the request schema is to be
  confirmed against fiskaly's TEST environment before the first live box.
  """

  @behaviour Palee.Fiscal.Ports.CashRegisterSecurity

  alias Palee.Fiscal.Domain.RksvReceipt
  alias Palee.Infrastructure.Fiscal.Http

  @base_url "https://rksv.fiskaly.com/api/v1"

  @doc """
  «Δοκιμή σύνδεσης» (ADR-273): signs in and reads the signature creation
  unit and the cash register Palee provisioned. Nothing is signed.
  """
  @impl true
  def check(connection) do
    steps = fn token ->
      with {:ok, _unit} <-
             found(request(token, :get, "/signature-creation-unit/" <> connection.unit_id, nil)),
           {:ok, register} <-
             found(request(token, :get, "/cash-register/" <> connection.register_id, nil)) do
        if register["state"] in ["INITIALIZED", nil],
          do: {:ok, %{}},
          else: {:error, :unit_not_ready}
      end
    end

    {result, _wire} = with_token(connection, steps, nil)
    result
  end

  defp found({:error, {:not_found, _body}}), do: {:error, :unit_not_found}
  defp found(result), do: result

  @impl true
  def provision(connection, context) do
    scu = "/signature-creation-unit/" <> connection.unit_id
    register = "/cash-register/" <> connection.register_id

    steps = fn token ->
      with {:ok, _scu} <-
             request(token, :put, scu, %{
               legal_entity_id: %{vat_id: context[:vat_number]},
               legal_entity_name: context[:legal_name]
             }),
           {:ok, unit} <- request(token, :patch, scu, %{state: "INITIALIZED"}),
           {:ok, _register} <- request(token, :put, register, %{description: "Palee"}),
           {:ok, _registered} <- request(token, :patch, register, %{state: "REGISTERED"}),
           {:ok, initialized} <- request(token, :patch, register, %{state: "INITIALIZED"}) do
        start =
          case request(token, :get, register <> "/receipt/1", nil) do
            {:ok, receipt} -> signature(receipt)
            _not_yet -> nil
          end

        {:ok,
         %{
           unit_serial: unit["certificate_serial_number"],
           register_serial:
             initialized["serial_number"] || initialized["cash_register_serial_number"],
           public_key: nil,
           admin_pin: nil,
           start: start
         }}
      end
    end

    with_token(connection, steps, nil)
  end

  @impl true
  def sign(connection, %{external_id: id, schema: schema}) do
    body = %{receipt_type: "NORMAL", schema: schema}

    with_token(
      connection,
      fn token ->
        with {:ok, receipt} <-
               request(
                 token,
                 :put,
                 "/cash-register/#{connection.register_id}/receipt/#{id}",
                 body
               ) do
          {:ok, signature(receipt)}
        end
      end,
      Jason.encode!(body)
    )
  end

  @impl true
  def lookup(connection, %{external_id: id}) do
    with_token(
      connection,
      fn token ->
        case request(token, :get, "/cash-register/#{connection.register_id}/receipt/#{id}", nil) do
          {:ok, %{"signed" => false}} -> {:error, :not_found}
          {:ok, receipt} -> {:ok, signature(receipt)}
          {:error, {:not_found, _body}} -> {:error, :not_found}
          {:error, {:uncertain, reason}} -> {:error, {:transient, reason}}
          other -> other
        end
      end,
      nil
    )
  end

  defp signature(receipt) do
    code = receipt["qr_code_data"]
    parsed = with {:ok, parsed} <- RksvReceipt.parse_code(code), do: parsed, else: (_ -> %{})
    hints = receipt["hints"] |> List.wrap() |> Enum.map(&to_string/1)

    outage? =
      Enum.any?(hints, &String.contains?(&1, RksvReceipt.failed_marker())) or
        parsed[:device_failed] == true

    %{
      transaction_number: integer(receipt["receipt_number"]),
      signature_counter: nil,
      signature_value: parsed[:signature] || code,
      signature_algorithm: "ES256",
      time_format: "unixTime",
      started_at_device: time(receipt["time_signature"]),
      finished_at_device: time(receipt["time_signature"]),
      unit_serial: parsed[:certificate_serial],
      register_serial: receipt["cash_register_serial_number"] || parsed[:register_id],
      receipt_number: receipt["receipt_number"] && to_string(receipt["receipt_number"]),
      qr_code_data: code,
      device_failed: outage?,
      hint: if(outage?, do: RksvReceipt.failed_marker())
    }
  end

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> nil
    end
  end

  defp integer(_value), do: nil

  defp time(seconds) when is_integer(seconds),
    do: %{DateTime.from_unix!(seconds) | microsecond: {0, 6}}

  defp time(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> %{at | microsecond: {elem(at.microsecond, 0), 6}}
      _other -> nil
    end
  end

  defp time(_value), do: nil

  # ── HTTP ────────────────────────────────────────────────────────────────

  defp with_token(connection, steps, logged_request) do
    Process.delete(:fiskaly_at_last_response)

    result =
      with :ok <- credentials(connection),
           {:ok, token} <- authenticate(connection) do
        steps.(token)
      end

    {status, body} = Process.delete(:fiskaly_at_last_response) || {nil, nil}

    result =
      case result do
        {:error, {:not_found, body}} ->
          {:error, {:rejected, [%{code: "not_found", message: inspect(body)}]}}

        other ->
          other
      end

    {result, Http.wire(logged_request, status, body)}
  end

  defp credentials(%{api_key: key, api_secret: secret})
       when is_binary(key) and key != "" and is_binary(secret) and secret != "",
       do: :ok

  defp credentials(_connection), do: {:error, {:unauthorized, :credentials_missing}}

  defp authenticate(connection) do
    case request(nil, :post, "/auth", %{
           api_key: connection.api_key,
           api_secret: connection.api_secret
         }) do
      {:ok, %{"access_token" => token}} -> {:ok, token}
      {:ok, _other} -> {:error, {:unauthorized, :no_token}}
      {:error, {:rejected, _}} -> {:error, {:unauthorized, :auth_refused}}
      {:error, {:uncertain, reason}} -> {:error, {:transient, reason}}
      error -> error
    end
  end

  defp request(token, method, path, body) do
    [
      method: method,
      url: base_url() <> path,
      headers: if(token, do: [{"authorization", "Bearer " <> token}], else: [])
    ]
    |> then(fn options -> if body, do: Keyword.put(options, :json, body), else: options end)
    |> Http.request()
    |> case do
      {:ok, response} ->
        unless path == "/auth",
          do: Process.put(:fiskaly_at_last_response, {response.status, response.body})

        interpret(response)

      error ->
        error
    end
  end

  defp interpret(%Req.Response{status: 404} = response),
    do: {:error, {:not_found, Http.json(response)}}

  defp interpret(response) do
    with {:ok, response} <- Http.classify(response) do
      body = Http.json(response)

      cond do
        response.status in 200..299 ->
          {:ok, body}

        response.status in 400..499 ->
          {:error,
           {:rejected,
            [%{code: body["code"] || to_string(response.status), message: body["message"] || ""}]}}

        true ->
          {:error, {:http, response.status}}
      end
    end
  end

  defp base_url do
    :palee
    |> Application.get_env(:fiskaly_sign_at, [])
    |> Keyword.get(:base_url, @base_url)
    |> String.trim_trailing("/")
  end
end
