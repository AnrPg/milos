defmodule MilosTraining.Infrastructure.Security.MemoryRateLimiter do
  @table :milos_training_rate_limits

  def check_rate(key, interval_ms, max) do
    check_rate(key, interval_ms, max, now_ms: System.system_time(:millisecond))
  end

  def check_rate(key, interval_ms, max, opts) do
    ensure_table!()
    now = Keyword.fetch!(opts, :now_ms)

    entries =
      case :ets.lookup(@table, key) do
        [{^key, timestamps}] -> timestamps
        [] -> []
      end
      |> Enum.filter(&(&1 > now - interval_ms))

    if length(entries) >= max do
      true = :ets.insert(@table, {key, entries})
      {:error, length(entries)}
    else
      updated_entries = [now | entries]
      true = :ets.insert(@table, {key, updated_entries})
      {:ok, length(updated_entries)}
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
