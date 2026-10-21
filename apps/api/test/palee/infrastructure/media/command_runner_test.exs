defmodule Palee.Infrastructure.Media.CommandRunnerTest do
  use ExUnit.Case, async: true

  alias Palee.Infrastructure.Media.CommandRunner

  test "a tool that exits at once still reports its status" do
    true_bin = System.find_executable("true")
    false_bin = System.find_executable("false")

    for _ <- 1..200 do
      assert {:ok, ""} = CommandRunner.run(true_bin, [], 5_000)
      assert {:error, {:exit, 1, ""}} = CommandRunner.run(false_bin, [], 5_000)
    end
  end

  test "a tool past its limit is killed" do
    assert {:error, :timeout} = CommandRunner.run(System.find_executable("sleep"), ["5"], 100)
  end
end
