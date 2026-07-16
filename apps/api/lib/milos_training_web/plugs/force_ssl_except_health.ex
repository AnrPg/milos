defmodule MilosTrainingWeb.Plugs.ForceSslExceptHealth do
  @moduledoc """
  Applies production SSL redirects while allowing Kubernetes-style health probes
  to hit the dedicated health endpoint over internal HTTP.
  """

  @behaviour Plug

  @health_path ["api", "health"]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{path_info: @health_path} = conn, _opts) do
    if internal_probe?(conn.remote_ip) do
      conn
    else
      enforce_ssl(conn)
    end
  end

  def call(conn, _opts), do: enforce_ssl(conn)

  defp enforce_ssl(conn) do
    case Application.get_env(:milos_training, :force_ssl) do
      opts when is_list(opts) ->
        Plug.SSL.call(conn, Plug.SSL.init(opts))

      _disabled ->
        conn
    end
  end

  defp internal_probe?({127, 0, 0, 1}), do: true
  defp internal_probe?({10, _, _, _}), do: true
  defp internal_probe?({172, second, _, _}) when second in 16..31, do: true
  defp internal_probe?({192, 168, _, _}), do: true
  defp internal_probe?({0, 0, 0, 0, 0, 0, 0, 1}), do: true

  defp internal_probe?({first, _, _, _, _, _, _, _}) when Bitwise.band(first, 0xFE00) == 0xFC00,
    do: true

  defp internal_probe?(_remote_ip), do: false
end
