defmodule MilosTrainingWeb.Plugs.RateLimit do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias MilosTraining.Infrastructure.Security.RateLimiter

  def init(opts), do: opts

  def call(conn, opts) do
    methods = Keyword.get(opts, :methods)

    if methods && conn.method not in methods do
      conn
    else
      check_rate(conn, opts)
    end
  end

  defp check_rate(conn, opts) do
    max = Keyword.fetch!(opts, :max)
    interval = Keyword.fetch!(opts, :interval)
    bucket = Keyword.get(opts, :bucket, conn.request_path)
    key = "#{conn.method}:#{bucket}:#{actor_identifier(conn)}:#{client_identifier(conn)}"

    case RateLimiter.check_rate(key, interval, max) do
      {:ok, _count} ->
        conn

      {:error, count} when is_integer(count) ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{code: "rate_limited", error: "Too many requests"})
        |> halt()

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{code: "rate_limiter_unavailable", error: "Rate limiter unavailable"})
        |> halt()
    end
  end

  defp actor_identifier(conn) do
    case conn.assigns[:user_context] do
      %{user_id: id} when is_binary(id) -> id
      _other -> "anonymous"
    end
  end

  defp client_identifier(conn) do
    conn.remote_ip |> Tuple.to_list() |> Enum.join(".")
  end
end
