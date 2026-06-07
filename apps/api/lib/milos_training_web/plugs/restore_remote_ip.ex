defmodule MilosTrainingWeb.Plugs.RestoreRemoteIp do
  @moduledoc false

  import Plug.Conn

  @default_headers ["x-forwarded-for"]
  @default_proxies [
    {127, 0, 0, 1},
    {10, 0, 0, 0, 8},
    {172, 16, 0, 0, 12},
    {192, 168, 0, 0, 16}
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    options =
      Application.get_env(
        :milos_training,
        :remote_ip,
        headers: @default_headers,
        proxies: @default_proxies
      )

    if trusted_proxy?(conn.remote_ip, Keyword.get(options, :proxies, @default_proxies)) do
      proxies = Keyword.get(options, :proxies, @default_proxies)

      case forwarded_ip(conn, Keyword.get(options, :headers, @default_headers), proxies) do
        nil -> conn
        remote_ip -> %{conn | remote_ip: remote_ip}
      end
    else
      conn
    end
  end

  defp forwarded_ip(conn, headers, proxies) do
    headers
    |> Enum.find_value(fn header ->
      case get_req_header(conn, header) do
        [value | _] -> parse_forwarded_for(value, proxies)
        _ -> nil
      end
    end)
  end

  defp parse_forwarded_for(value, proxies) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reverse()
    |> Enum.reduce_while(nil, fn candidate, _acc ->
      case :inet.parse_address(String.to_charlist(candidate)) do
        {:ok, remote_ip} ->
          if trusted_proxy?(remote_ip, proxies) do
            {:cont, nil}
          else
            {:halt, remote_ip}
          end

        {:error, _reason} ->
          {:cont, nil}
      end
    end)
  end

  defp trusted_proxy?(remote_ip, proxies) when is_tuple(remote_ip) do
    Enum.any?(proxies, &ip_match?(remote_ip, &1))
  end

  defp ip_match?(ip, ip), do: true

  defp ip_match?({a, b, c, d}, {pa, pb, pc, pd, prefix}) do
    prefix_match?({a, b, c, d}, {pa, pb, pc, pd}, prefix)
  end

  defp ip_match?(_ip, _proxy), do: false

  defp prefix_match?(ip, proxy, prefix) do
    ip
    |> ipv4_to_int()
    |> Bitwise.bsr(32 - prefix) == Bitwise.bsr(ipv4_to_int(proxy), 32 - prefix)
  end

  defp ipv4_to_int({a, b, c, d}) do
    Bitwise.bsl(a, 24) + Bitwise.bsl(b, 16) + Bitwise.bsl(c, 8) + d
  end
end
