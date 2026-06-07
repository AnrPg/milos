defmodule MilosTrainingWeb.Plugs.Cors do
  @moduledoc false

  import Plug.Conn

  @behaviour Plug

  @allowed_methods "GET,POST,PUT,PATCH,DELETE,OPTIONS"
  @default_allowed_headers "authorization,content-type,accept"

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "origin") do
      [origin] ->
        if origin_allowed?(origin) do
          conn
          |> maybe_handle_preflight(origin)
          |> register_cors_headers(origin)
        else
          conn
        end

      _ ->
        conn
    end
  end

  def default_origins do
    host = System.get_env("PHX_HOST", "localhost")

    [
      "http://#{host}:#{System.get_env("WEB_HOST_PORT", "18300")}",
      "http://#{host}:#{System.get_env("CADDY_HTTP_HOST_PORT", "18080")}",
      "https://#{host}:#{System.get_env("CADDY_HTTPS_HOST_PORT", "18443")}",
      "http://127.0.0.1:#{System.get_env("WEB_HOST_PORT", "18300")}",
      "http://127.0.0.1:#{System.get_env("CADDY_HTTP_HOST_PORT", "18080")}",
      "https://127.0.0.1:#{System.get_env("CADDY_HTTPS_HOST_PORT", "18443")}"
    ]
  end

  defp maybe_handle_preflight(%Plug.Conn{method: "OPTIONS"} = conn, origin) do
    requested_headers =
      conn
      |> get_req_header("access-control-request-headers")
      |> List.first()
      |> case do
        nil -> @default_allowed_headers
        headers -> headers
      end

    conn
    |> put_resp_header("access-control-allow-origin", origin)
    |> put_resp_header("access-control-allow-methods", @allowed_methods)
    |> put_resp_header("access-control-allow-headers", requested_headers)
    |> put_resp_header("access-control-max-age", "86400")
    |> put_resp_header(
      "vary",
      "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
    )
    |> send_resp(:no_content, "")
    |> halt()
  end

  defp maybe_handle_preflight(conn, _origin), do: conn

  defp register_cors_headers(%Plug.Conn{halted: true} = conn, _origin), do: conn

  defp register_cors_headers(conn, origin) do
    register_before_send(conn, fn conn ->
      conn
      |> put_resp_header("access-control-allow-origin", origin)
      |> put_resp_header("access-control-allow-methods", @allowed_methods)
      |> put_resp_header("access-control-allow-headers", @default_allowed_headers)
      |> put_resp_header("vary", "Origin")
    end)
  end

  defp origin_allowed?(origin), do: origin in default_origins()
end
