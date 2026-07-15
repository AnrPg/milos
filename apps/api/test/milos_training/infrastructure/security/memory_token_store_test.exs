defmodule MilosTraining.Infrastructure.Security.MemoryTokenStoreTest do
  use ExUnit.Case, async: false

  alias MilosTraining.Infrastructure.Security.MemoryTokenStore

  setup do
    MemoryTokenStore.reset!()
    :ok
  end

  test "only one concurrent caller consumes a refresh JTI" do
    results =
      1..20
      |> Task.async_stream(fn _ -> MemoryTokenStore.consume("shared-jti", 60_000) end,
        max_concurrency: 20
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == {:ok, true})) == 1
    assert Enum.count(results, &(&1 == {:ok, false})) == 19
  end
end
