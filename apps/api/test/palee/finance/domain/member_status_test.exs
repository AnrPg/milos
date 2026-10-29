defmodule Palee.Finance.Domain.MemberStatusTest do
  # ADR-274: the status staff see, worked out from subscriptions and charges.
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.{MemberStatus, OpenCharges, ValueOverride}

  @today ~D[2026-10-29]

  defp subscription(overrides \\ %{}) do
    Map.merge(
      %{
        status: "active",
        starts_on: ~D[2026-10-01],
        ends_on: nil,
        price_cents_snapshot: 5000,
        package_type: "membership",
        renews?: true,
        period_last_day: ~D[2026-10-31]
      },
      overrides
    )
  end

  defp facts(overrides \\ %{}) do
    Map.merge(
      %{
        today: @today,
        subscriptions: [subscription()],
        entitlement: %{status: "active", source: "membership_package"},
        grace_days: 3
      },
      overrides
    )
  end

  defp derive(overrides \\ %{}), do: MemberStatus.derive(facts(overrides))

  test "a running, paid, renewing subscription is active" do
    assert %{status: "active", lifecycle: "active"} = derive()
  end

  test "money owed shows in the status but never changes the stored lifecycle" do
    assert %{status: "unpaid", lifecycle: "active"} = derive(%{unpaid_due_on: @today})

    assert %{status: "overdue", lifecycle: "active"} =
             derive(%{
               unpaid_due_on: ~D[2026-10-01],
               entitlement: %{status: "blocked", source: "overdue_invoice"}
             })
  end

  test "a trial or a free package keeps its own kind" do
    assert %{status: "trial", lifecycle: "trial"} =
             derive(%{subscriptions: [subscription(%{package_type: "trial"})]})

    assert %{status: "comped", lifecycle: "comped"} =
             derive(%{subscriptions: [subscription(%{price_cents_snapshot: 0})]})

    assert %{status: "unpaid", lifecycle: "trial"} =
             derive(%{
               subscriptions: [subscription(%{package_type: "trial"})],
               unpaid_due_on: @today
             })
  end

  test "ending soon: an end date within 30 days, or renewal turned off" do
    assert %{status: "expiring"} =
             derive(%{subscriptions: [subscription(%{ends_on: ~D[2026-11-20]})]})

    assert %{status: "active"} =
             derive(%{subscriptions: [subscription(%{ends_on: ~D[2027-01-20]})]})

    assert %{status: "expiring", lifecycle: "expiring"} =
             derive(%{subscriptions: [subscription(%{renews?: false})]})
  end

  test "no running subscription: ended, keeping access through the grace days" do
    ended = subscription(%{ends_on: ~D[2026-10-27]})
    assert %{status: "expired", lifecycle: "expiring"} = derive(%{subscriptions: [ended]})

    long_ended = subscription(%{ends_on: ~D[2026-10-01]})
    assert %{status: "expired", lifecycle: "expired"} = derive(%{subscriptions: [long_ended]})
  end

  test "a subscription that has not begun says nothing yet" do
    future = subscription(%{starts_on: ~D[2026-11-10]})
    assert %{status: "no_package", lifecycle: "active"} = derive(%{subscriptions: [future]})
  end

  test "a profile without packages follows its own dates" do
    assert %{status: "no_package"} = derive(%{subscriptions: []})

    assert %{status: "expiring", lifecycle: "expiring"} =
             derive(%{subscriptions: [], membership_expires_on: ~D[2026-11-10]})

    assert %{status: "expired", lifecycle: "expired"} =
             derive(%{subscriptions: [], membership_expires_on: ~D[2026-10-01]})
  end

  test "leaving, left, paused and frozen" do
    left_at = DateTime.utc_now()

    assert %{status: "leaving", lifecycle: "active"} =
             derive(%{left_at: left_at, leaving_on: ~D[2026-11-30]})

    assert %{status: "cancelled", lifecycle: "cancelled"} =
             derive(%{left_at: left_at, leaving_on: @today})

    assert %{status: "paused", lifecycle: "paused"} =
             derive(%{subscriptions: [subscription(%{status: "paused"})]})

    # A freeze shows as paused but keeps the membership's state (ADR-097).
    assert %{status: "paused", lifecycle: "active"} = derive(%{frozen?: true})
  end

  test "the order of precedence: paused beats money owed, money owed beats ending soon" do
    assert %{status: "paused"} = derive(%{frozen?: true, unpaid_due_on: @today})

    assert %{status: "unpaid"} =
             derive(%{
               subscriptions: [subscription(%{ends_on: ~D[2026-11-05]})],
               unpaid_due_on: @today
             })
  end

  test "overrides: values staff may set, and when a status override lapses" do
    assert {:ok, "active"} = ValueOverride.validate("status", "active")
    assert {:error, :invalid_override_value} = ValueOverride.validate("status", "unpaid")
    assert {:ok, "2026-12-01"} = ValueOverride.validate("ends_on", "2026-12-01")
    assert {:error, :invalid_override_value} = ValueOverride.validate("ends_on", "soon")
    assert {:error, :invalid_override_field} = ValueOverride.validate("price", "1")

    status_override = %{field: "status", computed_value: "unpaid"}
    refute ValueOverride.lapsed?(status_override, "unpaid")
    assert ValueOverride.lapsed?(status_override, "active")
    refute ValueOverride.lapsed?(%{field: "ends_on", computed_value: nil}, "2026-12-01")

    assert ValueOverride.reason("  ") == nil
    assert String.length(ValueOverride.reason(String.duplicate("a", 900))) == 500
  end

  test "where a debt stands" do
    assert OpenCharges.state(~D[2026-11-01], 3, @today) == "upcoming"
    assert OpenCharges.state(@today, 3, @today) == "unpaid"
    assert OpenCharges.state(~D[2026-10-26], 3, @today) == "unpaid"
    assert OpenCharges.state(~D[2026-10-25], 3, @today) == "overdue"
  end
end
