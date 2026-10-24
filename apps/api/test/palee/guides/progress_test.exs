defmodule Palee.Guides.Domain.ProgressTest do
  use ExUnit.Case, async: true

  alias Palee.Guides.Domain.Progress

  @t0 ~U[2026-10-24 08:00:00.000000Z]
  @t1 ~U[2026-10-24 08:05:00.000000Z]
  @t2 ~U[2026-10-24 09:00:00.000000Z]

  defp change(status, step \\ 0, version \\ 1),
    do: %{status: status, step: step, version: version}

  test "parses a change and refuses bad fields" do
    assert {:ok, %{status: "started", step: 0, version: 1}} =
             Progress.parse_change(%{"status" => "started"})

    assert {:error, errors} =
             Progress.parse_change(%{"status" => "done", "step" => 100, "version" => 0})

    assert Keyword.keys(errors) == [:status, :step, :version]
    assert {:error, [body: _]} = Progress.parse_change("x")
  end

  test "guide ids are short snake case" do
    assert :ok = Progress.validate_id("shop_staff")
    assert {:error, :not_found} = Progress.validate_id("Shop")
    assert {:error, :not_found} = Progress.validate_id(String.duplicate("a", 49))
  end

  test "a first start, steps and the first finish" do
    row = Progress.apply_change(nil, change("started"), @t0)
    assert %{runs: 1, started_at: @t0, completed_at: nil, step: 0} = row

    row = Progress.apply_change(row, change("started", 3), @t1)
    assert %{runs: 1, started_at: @t0, step: 3} = row

    done = Progress.apply_change(row, change("completed", 6), @t1)
    assert %{status: "completed", completed_at: @t1, runs: 1} = done

    again = Progress.apply_change(done, change("completed", 6), @t2)
    assert again.completed_at == @t1
  end

  test "starting again after a finish or a «not now» is a new run" do
    done = %{Progress.apply_change(nil, change("completed", 5), @t0) | step: 5}
    replay = Progress.apply_change(done, change("started"), @t2)
    assert %{runs: 2, started_at: @t2, completed_at: nil, status: "started"} = replay

    dismissed = Progress.apply_change(nil, change("dismissed"), @t0)
    assert %{runs: 2} = Progress.apply_change(dismissed, change("started"), @t1)
  end

  test "a newer version of a guide starts a new run" do
    done = Progress.apply_change(nil, change("completed", 5, 1), @t0)
    newer = Progress.apply_change(done, change("started", 0, 2), @t1)
    assert %{version: 2, runs: 2, completed_at: nil} = newer
  end

  test "the guide limit only stops new guides" do
    assert Progress.over_limit?(Progress.max_guides(), false)
    refute Progress.over_limit?(Progress.max_guides(), true)
    refute Progress.over_limit?(0, false)
  end
end
