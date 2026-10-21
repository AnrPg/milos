defmodule Palee.Infrastructure.Observability.MetricsPlug do
  @moduledoc """
  Minimal Plug served by the dedicated internal metrics listener (see
  `PaleeWeb.Telemetry`). It is intentionally NOT mounted in the public
  Phoenix endpoint: the listener binds its own port that Compose never
  publishes and Caddy never proxies. When a token is configured, scrapes must
  present it as `Authorization: Bearer <token>` (constant-time compared via :crypto.hash_equals).
  """

  @behaviour Plug

  import Plug.Conn

  alias Palee.Infrastructure.Observability.PrometheusExporter

  @impl true
  def init(options) do
    %{
      exporter: Keyword.get(options, :exporter, PrometheusExporter),
      token: Keyword.get(options, :token)
    }
  end

  @impl true
  def call(%Plug.Conn{method: "GET", path_info: ["metrics"]} = conn, options) do
    if authorized?(conn, options.token) do
      conn
      |> put_resp_content_type("text/plain; version=0.0.4")
      |> send_resp(200, PrometheusExporter.scrape(options.exporter))
    else
      conn
      |> put_resp_header("www-authenticate", ~s(Bearer realm="metrics"))
      |> send_resp(401, "unauthorized\n")
    end
  end

  def call(conn, _options), do: send_resp(conn, 404, "not found\n")

  defp authorized?(_conn, nil), do: true

  defp authorized?(conn, token) do
    case get_req_header(conn, "authorization") do
      # Hashing first gives equal-length inputs to the constant-time compare.
      ["Bearer " <> presented] -> :crypto.hash_equals(digest(presented), digest(token))
      _other -> false
    end
  end

  defp digest(value), do: :crypto.hash(:sha256, value)
end
