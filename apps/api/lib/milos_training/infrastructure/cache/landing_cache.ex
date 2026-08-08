defmodule MilosTraining.Infrastructure.Cache.LandingCache do
  @behaviour MilosTraining.Application.Ports.LandingCache
  @ttl_seconds 60

  alias MilosTraining.Application.OwnershipKeys

  def get_or_fetch(%{organization_id: organization_id}, user_id, fetch_fun)
      when is_binary(organization_id) and is_function(fetch_fun, 0) do
    case get(organization_id, user_id) do
      {:ok, payload} ->
        payload

      :miss ->
        payload = fetch_fun.()
        put(organization_id, user_id, payload)
        payload
    end
  end

  def get_or_fetch(_context, _user_id, _fetch_fun), do: {:error, :organization_context_required}

  def invalidate(user_id) do
    batch_invalidate([user_id])
  end

  def batch_invalidate([]), do: :ok

  def batch_invalidate(user_ids) when is_list(user_ids) do
    with {:ok, redix} <- redix() do
      user_ids
      |> Enum.flat_map(&landing_keys_for_user(redix, &1))
      |> case do
        [] -> :ok
        keys -> Redix.command(redix, ["DEL" | keys])
      end
    end

    :ok
  end

  defp get(organization_id, user_id) do
    with {:ok, redix} <- redix(),
         {:ok, cached} when not is_nil(cached) <-
           Redix.command(redix, ["GET", cache_key(organization_id, user_id)]),
         {:ok, payload} <- Jason.decode(cached) do
      {:ok, payload}
    else
      _ -> :miss
    end
  end

  defp put(organization_id, user_id, payload) do
    with {:ok, redix} <- redix() do
      _ =
        Redix.command(redix, [
          "SETEX",
          cache_key(organization_id, user_id),
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

  defp cache_key(organization_id, user_id),
    do: OwnershipKeys.tenant(%{organization_id: organization_id}, "landing:#{user_id}")

  defp landing_keys_for_user(redix, user_id) do
    scan_landing_keys(redix, "0", "*:landing:#{user_id}", [])
  end

  defp scan_landing_keys(redix, cursor, pattern, acc) do
    case Redix.command(redix, ["SCAN", cursor, "MATCH", pattern, "COUNT", "100"]) do
      {:ok, ["0", keys]} -> acc ++ keys
      {:ok, [next_cursor, keys]} -> scan_landing_keys(redix, next_cursor, pattern, acc ++ keys)
      _error -> acc
    end
  end
end
