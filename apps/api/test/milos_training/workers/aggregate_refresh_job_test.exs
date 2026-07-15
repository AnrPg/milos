defmodule MilosTraining.Workers.AggregateRefreshJobTest do
  use ExUnit.Case, async: false

  alias MilosTraining.Workers.{RefreshCoachingAggregatesJob, RefreshFinanceAggregatesJob}

  setup do
    previous_finance = Application.get_env(:milos_training, :finance_store)
    previous_coaching = Application.get_env(:milos_training, :coaching_store)

    Application.put_env(:milos_training, :finance_store, __MODULE__.FinanceStore)
    Application.put_env(:milos_training, :coaching_store, __MODULE__.CoachingStore)

    on_exit(fn ->
      restore_env(:finance_store, previous_finance)
      restore_env(:coaching_store, previous_coaching)
    end)

    :ok
  end

  test "finance refresh worker does not call coaching refresh" do
    Process.register(self(), :aggregate_refresh_job_test)
    Process.put(:finance_result, {:error, :finance_down})

    assert {:error, :finance_down} =
             RefreshFinanceAggregatesJob.perform(%Oban.Job{args: %{}})

    assert_received :finance_refreshed
    refute_received :coaching_refreshed
  after
    unregister_test_process()
  end

  test "coaching refresh worker runs independently" do
    Process.register(self(), :aggregate_refresh_job_test)

    assert :ok = RefreshCoachingAggregatesJob.perform(%Oban.Job{args: %{}})

    assert_received :coaching_refreshed
    refute_received :finance_refreshed
  after
    unregister_test_process()
  end

  defp restore_env(key, nil), do: Application.delete_env(:milos_training, key)
  defp restore_env(key, value), do: Application.put_env(:milos_training, key, value)

  defp unregister_test_process do
    if Process.whereis(:aggregate_refresh_job_test) == self() do
      Process.unregister(:aggregate_refresh_job_test)
    end
  end

  defmodule FinanceStore do
    def refresh_aggregates do
      send(Process.whereis(:aggregate_refresh_job_test), :finance_refreshed)
      Process.get(:finance_result, :ok)
    end
  end

  defmodule CoachingStore do
    def refresh_aggregates do
      send(Process.whereis(:aggregate_refresh_job_test), :coaching_refreshed)
      :ok
    end
  end
end
