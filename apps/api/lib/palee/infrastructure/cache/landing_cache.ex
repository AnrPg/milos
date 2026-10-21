defmodule Palee.Infrastructure.Cache.LandingCache do
  @behaviour Palee.Application.Ports.LandingCache
  @ttl_seconds 60

  alias Palee.Application.OwnershipKeys

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

  # Invalidation stays best-effort (the 60s TTL bounds staleness), but each
  # outcome is reported so failed invalidations are visible on dashboards.
  def batch_invalidate(user_ids) when is_list(user_ids) do
    result =
      with {:ok, redix} <- redix() do
        user_ids
        |> Enum.flat_map(&landing_keys_for_user(redix, &1))
        |> case do
          [] -> :ok
          keys -> Redix.command(redix, ["DEL" | keys])
        end
      end

    emit_state("invalidate", invalidation_result(result), %{keys: length(user_ids)})
    :ok
  end

  defp invalidation_result(:error), do: "unavailable"
  defp invalidation_result({:error, _reason}), do: "error"
  defp invalidation_result(_ok), do: "ok"

  defp get(organization_id, user_id) do
    case redix() do
      {:ok, redix} ->
        redix
        |> Redix.command(["GET", cache_key(organization_id, user_id)])
        |> decode_cached()

      :error ->
        emit_state("read", "unavailable")
        :miss
    end
  end

  defp decode_cached({:ok, cached}) when is_binary(cached) do
    case Jason.decode(cached) do
      {:ok, payload} ->
        emit_state("read", "hit")
        {:ok, payload}

      {:error, _reason} ->
        emit_state("read", "error")
        :miss
    end
  end

  defp decode_cached({:ok, nil}) do
    emit_state("read", "miss")
    :miss
  end

  defp decode_cached(_error) do
    emit_state("read", "error")
    :miss
  end

  defp emit_state(operation, result, measurements \\ %{}) do
    :telemetry.execute(
      [:palee, :cache, :state],
      Map.put(measurements, :count, 1),
      %{cache: "landing", operation: operation, result: result}
    )
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
