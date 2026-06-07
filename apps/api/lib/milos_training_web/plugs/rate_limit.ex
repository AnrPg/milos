defmodule MilosTrainingWeb.Plugs.RateLimit do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias MilosTraining.Infrastructure.Security.RateLimiter

  def init(opts), do: opts

  def call(conn, opts) do
    max = Keyword.fetch!(opts, :max)
    interval = Keyword.fetch!(opts, :interval)
    key = "#{conn.method}:#{conn.request_path}:#{client_identifier(conn)}"

    case RateLimiter.check_rate(key, interval, max) do
      {:ok, _count} ->
        conn

      {:error, count} when is_integer(count) ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "Too many requests"})
        |> halt()

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "Rate limiter unavailable"})
        |> halt()
    end
  end

  defp client_identifier(conn) do
    conn.remote_ip |> Tuple.to_list() |> Enum.join(".")
  end
end
