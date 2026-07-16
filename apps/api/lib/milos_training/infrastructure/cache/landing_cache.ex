defmodule MilosTraining.Infrastructure.Cache.LandingCache do
  @behaviour MilosTraining.Application.Ports.LandingCache
  @ttl_seconds 60

  def get_or_fetch(user_id, fetch_fun) when is_function(fetch_fun, 0) do
    case get(user_id) do
      {:ok, payload} ->
        payload

      :miss ->
        payload = fetch_fun.()
        put(user_id, payload)
        payload
    end
  end

  def invalidate(user_id) do
    batch_invalidate([user_id])
  end

  def batch_invalidate([]), do: :ok

  def batch_invalidate(user_ids) when is_list(user_ids) do
    with {:ok, redix} <- redix() do
      commands = Enum.map(user_ids, fn id -> ["DEL", cache_key(id)] end)
      _ = Redix.pipeline(redix, commands)
    end

    :ok
  end

  defp get(user_id) do
    with {:ok, redix} <- redix(),
         {:ok, cached} when not is_nil(cached) <-
           Redix.command(redix, ["GET", cache_key(user_id)]),
         {:ok, payload} <- Jason.decode(cached) do
      {:ok, payload}
    else
      _ -> :miss
    end
  end

  defp put(user_id, payload) do
    with {:ok, redix} <- redix() do
      _ =
        Redix.command(redix, [
          "SETEX",
          cache_key(user_id),
          Integer.to_string(@ttl_seconds),
          Jason.encode!(payload)
        ])
    end

    payload
  end

  defp redix do
    case Process.whereis(:redix) do
      nil -> :error
      pid -> {:ok, pid}
    end
  end

  defp cache_key(user_id), do: "landing:#{user_id}"
end
