defmodule MilosTraining.Infrastructure.Security.MemoryTokenStore do
  @table :milos_training_revoked_tokens

  def revoke(nil, _ttl_ms), do: {:error, :invalid_jti}
  def revoke(_jti, ttl_ms) when ttl_ms <= 0, do: {:error, :invalid_ttl}

  def revoke(jti, ttl_ms) do
    ensure_table!()
    expires_at = System.system_time(:millisecond) + ttl_ms
    true = :ets.insert(@table, {jti, expires_at})
    :ok
  end

  def revoked?(nil), do: {:error, :invalid_jti}

  def revoked?(jti) do
    ensure_table!()
    now = System.system_time(:millisecond)

    case :ets.lookup(@table, jti) do
      [{^jti, expires_at}] ->
        if expires_at > now do
          {:ok, true}
        else
          :ets.delete(@table, jti)
          {:ok, false}
        end

      [] ->
        {:ok, false}
    end
  end

  def consume(nil, _ttl_ms), do: {:error, :invalid_jti}
  def consume(_jti, ttl_ms) when ttl_ms <= 0, do: {:error, :invalid_ttl}

  def consume(jti, ttl_ms) do
    ensure_table!()
    now = System.system_time(:millisecond)
    expires_at = now + ttl_ms

    case :ets.insert_new(@table, {jti, expires_at}) do
      true ->
        {:ok, true}

      false ->
        case :ets.lookup(@table, jti) do
          [{^jti, current_expiry}] when current_expiry <= now ->
            :ets.delete_object(@table, {jti, current_expiry})
            consume(jti, ttl_ms)

          _ ->
            {:ok, false}
        end
    end
  end

  def reset! do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])

      _table ->
        @table
    end
  end
end
