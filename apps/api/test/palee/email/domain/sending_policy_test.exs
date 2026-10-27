defmodule Palee.Email.Domain.SendingPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Email.Domain.SendingPolicy

  @now ~U[2026-12-24 15:30:00.000000Z]
  @budget %{daily_budget: 280, hard_cap: 295}

  describe "throttle/3" do
    @rule %{min_interval_seconds: 60, max_per_day: 3}

    test "allows the first email and one after the interval" do
      assert :ok = SendingPolicy.throttle(@rule, %{count: 0, last_at: nil}, @now)

      assert :ok =
               SendingPolicy.throttle(@rule, %{count: 1, last_at: DateTime.add(@now, -61)}, @now)
    end

    test "refuses within the interval and past the daily maximum" do
      assert {:error, :throttled} =
               SendingPolicy.throttle(@rule, %{count: 1, last_at: DateTime.add(@now, -10)}, @now)

      assert {:error, :throttled} =
               SendingPolicy.throttle(
                 @rule,
                 %{count: 3, last_at: DateTime.add(@now, -3_600)},
                 @now
               )
    end

    test "a zero interval only counts" do
      rule = %{min_interval_seconds: 0, max_per_day: 2}
      assert :ok = SendingPolicy.throttle(rule, %{count: 1, last_at: @now}, @now)
    end

    test "every category has a default" do
      for category <- SendingPolicy.categories() do
        assert %{min_interval_seconds: _, max_per_day: _} =
                 SendingPolicy.default_throttle(category)
      end
    end
  end

  describe "budgets" do
    test "non-security mail is deferred to the next UTC day at the budget" do
      assert :send = SendingPolicy.on_send(:transactional, 279, @budget, @now)
      assert {:defer, until} = SendingPolicy.on_send(:account, 280, @budget, @now)
      assert until == ~U[2026-12-25 00:01:00.000000Z]
      assert {:defer, ^until} = SendingPolicy.on_enqueue(:transactional, 280, @budget, @now)
    end

    test "security mail goes past the budget until the hard cap, then is refused at enqueue" do
      assert :send = SendingPolicy.on_send(:security, 290, @budget, @now)
      assert :queue = SendingPolicy.on_enqueue(:security, 290, @budget, @now)
      assert {:defer, _until} = SendingPolicy.on_send(:security, 295, @budget, @now)
      assert {:error, :over_budget} = SendingPolicy.on_enqueue(:security, 295, @budget, @now)
    end

    test "the day starts at UTC midnight" do
      assert SendingPolicy.day_start(@now) == ~U[2026-12-24 00:00:00.000000Z]
    end
  end

  test "categories parse from their names only" do
    assert {:ok, :security} = SendingPolicy.category("security")
    assert {:ok, :account} = SendingPolicy.category(:account)
    assert :error = SendingPolicy.category("marketing")
  end

  test "the 80% budget warning fires for exactly one count a day (ADR-212)" do
    budget = %{daily_budget: 280, hard_cap: 295}

    assert SendingPolicy.budget_warning?(224, budget)
    refute SendingPolicy.budget_warning?(223, budget)
    refute SendingPolicy.budget_warning?(225, budget)
    assert SendingPolicy.budget_warning?(9, %{budget | daily_budget: 11})
    refute SendingPolicy.budget_warning?(0, %{budget | daily_budget: 0})
  end
end
