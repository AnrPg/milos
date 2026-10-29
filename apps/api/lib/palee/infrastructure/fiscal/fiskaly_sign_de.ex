defmodule Palee.Infrastructure.Fiscal.FiskalySignDe do
  @moduledoc """
  fiskaly SIGN DE v2, a cloud TSE (ADR-251).

    * Auth: `POST /api/v2/auth` with the API key and secret → bearer token.
    * Provisioning (`provision/2`): `PUT /tss/{tss_id}` (returns the admin
      PUK once) → `PATCH {state: UNINITIALIZED}` → `PATCH /admin`
      (`admin_puk`, `new_admin_pin`) → `POST /admin/auth` → `PATCH {state:
      INITIALIZED}` → `PUT /client/{client_id}` (`serial_number`) →
      `POST /admin/logout`. Palee chooses the TSS and client ids and a
      random admin PIN, kept encrypted.
    * Signing (`sign/2`): `PUT /tss/{tss_id}/tx/{tx_id}?tx_revision=1`
      `{state: ACTIVE}` then `?tx_revision=2` `{state: FINISHED, schema}`;
      the answer carries the transaction number, the start and end times
      and the signature with its counter, algorithm and public key, all
      from the TSE, and the DSFinV-K QR code.
    * Read-back (`lookup/2`): `GET /tss/{tss_id}/tx/{tx_id}`; a FINISHED
      transaction is the signature, an ACTIVE one is finished now (the TSE
      said it never got the finish), 404 means it never started.

  Base URL from config (`:palee, :fiskaly_sign_de, base_url:`); TEST and
  LIVE share it and are told apart by the API key. Spec:
  https://workspace.fiskaly.com/specs/sign-de-v2.json.
  """

  @behaviour Palee.Fiscal.Ports.CashRegisterSecurity

  alias Palee.Infrastructure.Fiscal.Http

  @base_url "https://kassensichv-middleware.fiskaly.com/api/v2"

  # ── Provisioning ────────────────────────────────────────────────────────

  @impl true
  def provision(connection, context) do
    pin = connection[:admin_pin] || random_pin()
    tss = "/tss/" <> connection.unit_id

    steps = fn token ->
      with {:ok, created} <- call(token, :put, tss, %{}),
           {:ok, _} <- call(token, :patch, tss, %{state: "UNINITIALIZED"}),
           {:ok, _} <-
             call(token, :patch, tss <> "/admin", %{
               admin_puk: created["admin_puk"],
               new_admin_pin: pin
             }),
           {:ok, _} <- call(token, :post, tss <> "/admin/auth", %{admin_pin: pin}),
           {:ok, initialized} <- call(token, :patch, tss, %{state: "INITIALIZED"}),
           {:ok, client} <-
             call(token, :put, tss <> "/client/" <> connection.register_id, %{
               serial_number: client_serial(context, connection)
             }),
           {:ok, _} <- call(token, :post, tss <> "/admin/logout", %{}) do
        {:ok,
         %{
           unit_serial: initialized["serial_number"] || created["serial_number"],
           register_serial: client["serial_number"],
           public_key: initialized["public_key"] || created["public_key"],
           admin_pin: pin,
           start: nil
         }}
      end
    end

    with_token(connection, steps, nil)
  end

  defp client_serial(context, connection) do
    base = context[:register_serial] || "PALEE-" <> String.slice(connection.register_id, 0, 8)
    String.replace(base, ~r/[^A-Za-z0-9 '()+,\-.:=?]/, "-") |> String.slice(0, 70)
  end

  defp random_pin, do: 12 |> :crypto.strong_rand_bytes() |> Base.encode32(padding: false) |> String.slice(0, 12)

  # ── Signing ─────────────────────────────────────────────────────────────

  @impl true
  def sign(connection, %{external_id: id, schema: schema}) do
    path = "/tss/#{connection.unit_id}/tx/#{id}"
    body = %{state: "FINISHED", client_id: connection.register_id, schema: schema}

    steps = fn token ->
      with {:ok, _active} <-
             call(token, :put, path <> "?tx_revision=1", %{
               state: "ACTIVE",
               client_id: connection.register_id
             }),
           {:ok, finished} <- call(token, :put, path <> "?tx_revision=2", body) do
        {:ok, signature(finished)}
      end
    end

    with_token(connection, steps, Jason.encode!(body))
  end

  @impl true
  def lookup(connection, %{external_id: id, schema: schema}) do
    path = "/tss/#{connection.unit_id}/tx/#{id}"

    steps = fn token ->
      case call(token, :get, path, nil) do
        {:ok, %{"state" => "FINISHED"} = tx} ->
          {:ok, signature(tx)}

        {:ok, %{"state" => "ACTIVE"} = tx} ->
          revision = (tx["latest_revision"] || 1) + 1

          with {:ok, finished} <-
                 call(token, :put, "#{path}?tx_revision=#{revision}", %{
                   state: "FINISHED",
                   client_id: connection.register_id,
                   schema: schema
                 }) do
            {:ok, signature(finished)}
          end

        {:ok, %{"state" => other}} ->
          {:error, {:rejected, [%{code: "tx_#{String.downcase(other)}", message: "Transaction #{other}"}]}}

        {:error, {:not_found, _body}} ->
          {:error, :not_found}

        # A read is always safe to repeat.
        {:error, {:uncertain, reason}} ->
          {:error, {:transient, reason}}

        other ->
          other
      end
    end

    with_token(connection, steps, nil)
  end

  defp signature(tx) do
    sig = tx["signature"] || %{}

    %{
      transaction_number: tx["number"],
      signature_counter: sig["counter"],
      signature_value: sig["value"],
      signature_algorithm: sig["algorithm"],
      time_format: get_in(tx, ["log", "timestamp_format"]),
      started_at_device: unix(tx["time_start"]),
      finished_at_device: unix(tx["time_end"]),
      unit_serial: tx["tss_serial_number"],
      register_serial: tx["client_serial_number"],
      receipt_number: nil,
      qr_code_data: tx["qr_code_data"],
      device_failed: false,
      hint: nil
    }
  end

  defp unix(seconds) when is_integer(seconds),
    do: %{DateTime.from_unix!(seconds) | microsecond: {0, 6}}
  defp unix(_seconds), do: nil

  # ── HTTP ────────────────────────────────────────────────────────────────

  # Runs `steps` with a fresh token; the wire log keeps the last response
  # and only the request body given (never the credentials).
  defp with_token(connection, steps, logged_request) do
    Process.delete(:fiskaly_last_response)

    result =
      with :ok <- credentials(connection),
           {:ok, token} <- authenticate(connection) do
        steps.(token)
      end

    {last_status, last_body} = Process.delete(:fiskaly_last_response) || {nil, nil}
    {normalize(result), Http.wire(logged_request, last_status, last_body)}
  end

  defp normalize({:error, {:not_found, body}}),
    do: {:error, {:rejected, [%{code: "not_found", message: inspect(body)}]}}

  defp normalize(result), do: result

  defp credentials(%{api_key: key, api_secret: secret})
       when is_binary(key) and key != "" and is_binary(secret) and secret != "",
       do: :ok

  defp credentials(_connection), do: {:error, {:unauthorized, :credentials_missing}}

  defp authenticate(connection) do
    case request(nil, :post, "/auth", %{api_key: connection.api_key, api_secret: connection.api_secret}) do
      {:ok, %{"access_token" => token}} -> {:ok, token}
      {:ok, _other} -> {:error, {:unauthorized, :no_token}}
      {:error, {:rejected, _}} -> {:error, {:unauthorized, :auth_refused}}
      # Nothing is written by authenticating: safe to try again.
      {:error, {:uncertain, reason}} -> {:error, {:transient, reason}}
      error -> error
    end
  end

  defp call(token, method, path, body), do: request(token, method, path, body)

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
        unless path == "/auth", do: Process.put(:fiskaly_last_response, {response.status, response.body})
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

        # 423: TSE defective, deleted, certificate expired – the device is out.
        response.status == 423 ->
          {:error, {:device_unavailable, body["code"]}}

        response.status in 400..499 ->
          {:error, {:rejected, [%{code: body["code"] || to_string(response.status), message: body["message"] || ""}]}}

        true ->
          {:error, {:http, response.status}}
      end
    end
  end

  defp base_url do
    :palee
    |> Application.get_env(:fiskaly_sign_de, [])
    |> Keyword.get(:base_url, @base_url)
    |> String.trim_trailing("/")
  end
end
