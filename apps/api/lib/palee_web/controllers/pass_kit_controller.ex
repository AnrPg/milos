defmodule PaleeWeb.PassKitController do
  @moduledoc """
  Apple's PassKit web service (ADR-155), called by iPhones for the passes
  they hold: register and unregister for updates, list the passes that
  changed, fetch the latest pass, and log. The pass's own
  `Authorization: ApplePass <token>` is the only credential; these routes are
  Apple's contract, not part of the app's OpenAPI.
  """

  use PaleeWeb, :controller

  alias Palee.Application.WalletPasses

  def register(
        conn,
        %{"device_id" => device, "pass_type_id" => type, "serial" => serial} = params
      ) do
    case WalletPasses.register_device(device, type, serial, auth(conn), params["pushToken"]) do
      {:ok, :created} -> send_resp(conn, 201, "")
      {:ok, :existing} -> send_resp(conn, 200, "")
      error -> refuse(conn, error)
    end
  end

  def unregister(conn, %{"device_id" => device, "pass_type_id" => type, "serial" => serial}) do
    case WalletPasses.unregister_device(device, type, serial, auth(conn)) do
      :ok -> send_resp(conn, 200, "")
      error -> refuse(conn, error)
    end
  end

  def serials(conn, %{"device_id" => device, "pass_type_id" => type} = params) do
    case WalletPasses.updated_serials(device, type, params["passesUpdatedSince"]) do
      {:ok, %{serials: serials, last_updated: tag}} ->
        json(conn, %{serialNumbers: serials, lastUpdated: tag})

      :none ->
        send_resp(conn, 204, "")

      error ->
        refuse(conn, error)
    end
  end

  def latest(conn, %{"pass_type_id" => type, "serial" => serial}) do
    case WalletPasses.latest(type, serial, auth(conn), if_modified_since(conn)) do
      {:ok, %{body: body, last_modified: last_modified}} ->
        conn
        |> put_resp_content_type("application/vnd.apple.pkpass", nil)
        |> put_resp_header("last-modified", http_date(last_modified))
        |> send_resp(200, body)

      :not_modified ->
        send_resp(conn, 304, "")

      error ->
        refuse(conn, error)
    end
  end

  def log(conn, params) do
    WalletPasses.log(params["logs"])
    send_resp(conn, 200, "")
  end

  defp refuse(conn, {:error, :unauthorized}), do: send_resp(conn, 401, "")
  defp refuse(conn, {:error, :not_found}), do: send_resp(conn, 404, "")
  defp refuse(conn, {:error, :pass_revoked}), do: send_resp(conn, 401, "")
  defp refuse(conn, {:error, :wallet_not_configured}), do: send_resp(conn, 503, "")
  defp refuse(conn, {:error, :bad_request}), do: send_resp(conn, 400, "")
  defp refuse(conn, {:error, %Ecto.Changeset{}}), do: send_resp(conn, 400, "")
  defp refuse(conn, _error), do: send_resp(conn, 500, "")

  defp auth(conn), do: conn |> get_req_header("authorization") |> List.first()

  defp if_modified_since(conn) do
    with [value | _] <- get_req_header(conn, "if-modified-since"),
         {:ok, at} <- parse_http_date(value) do
      at
    else
      _none -> nil
    end
  end

  defp http_date(%DateTime{} = at), do: Calendar.strftime(at, "%a, %d %b %Y %H:%M:%S GMT")

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  defp parse_http_date(value) do
    with [_day, day, month, year, time, "GMT"] <- String.split(value, " ", trim: true),
         index when is_integer(index) <- Enum.find_index(@months, &(&1 == month)),
         {:ok, date} <- Date.new(String.to_integer(year), index + 1, String.to_integer(day)),
         {:ok, time} <- Time.from_iso8601(time) do
      DateTime.new(date, time, "Etc/UTC")
    else
      _invalid -> :error
    end
  rescue
    _error -> :error
  end
end
