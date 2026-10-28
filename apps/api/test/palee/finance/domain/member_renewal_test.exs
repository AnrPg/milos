defmodule Palee.Finance.Domain.MemberRenewalTest do
  # ADR-220: the member's renewal choice and leaving the box.
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.{MemberRenewal, PackageContract}

  defp params(fields \\ %{}) do
    {:ok, contract} =
      PackageContract.normalize(%{"package_type" => "membership", "fields" => fields})

    PackageContract.to_params(contract)
  end

  defp subscription(attrs \\ %{}) do
    Map.merge(
      %{
        status: "active",
        starts_on: ~D[2026-01-31],
        ends_on: nil,
        ends_on_from_renewal_stop: false,
        billing_period_snapshot: "monthly",
        commitment_ends_on: nil,
        auto_renew: true,
        base_subscription_id: nil,
        corporate_client_id: nil,
        params_snapshot: params()
      },
      attrs
    )
  end

  describe "choice" do
    test "a renewing membership the member holds is theirs to decide" do
      assert MemberRenewal.choice_allowed?(subscription())
      assert MemberRenewal.auto_renew(subscription()) == true
      assert MemberRenewal.auto_renew(subscription(%{auto_renew: false})) == false
    end

    test "no choice for a package that does not renew, an add-on or a company seat" do
      no_renew = subscription(%{params_snapshot: params(%{"terms.auto_renew" => false})})
      assert MemberRenewal.auto_renew(no_renew) == nil
      assert MemberRenewal.auto_renew(subscription(%{base_subscription_id: "base"})) == nil
      assert MemberRenewal.auto_renew(subscription(%{corporate_client_id: "acme"})) == nil
      assert MemberRenewal.auto_renew(subscription(%{status: "expired"})) == nil
    end

    test "renewal invoices wait for the member's yes and stop when they leave" do
      assert :ok = MemberRenewal.renewal_allowed(subscription(), %{left_at: nil})

      assert {:error, :renewal_turned_off} =
               MemberRenewal.renewal_allowed(subscription(%{auto_renew: false}), %{left_at: nil})

      assert {:error, :member_leaving} =
               MemberRenewal.renewal_allowed(subscription(), %{left_at: DateTime.utc_now()})
    end
  end

  describe "last_day/3" do
    test "the end of the billing period today falls in, anchored on the start" do
      assert MemberRenewal.last_day(subscription(), [], ~D[2026-03-10]) == ~D[2026-03-30]
      assert MemberRenewal.last_day(subscription(), [], ~D[2026-03-31]) == ~D[2026-04-29]

      quarterly = subscription(%{billing_period_snapshot: "quarterly"})
      assert MemberRenewal.last_day(quarterly, [], ~D[2026-03-10]) == ~D[2026-04-29]

      semiannual = subscription(%{billing_period_snapshot: "semiannual"})
      assert MemberRenewal.last_day(semiannual, [], ~D[2026-03-10]) == ~D[2026-07-30]
    end

    test "a later paid period and a commitment are kept" do
      paid = [{~D[2026-04-30], ~D[2026-05-30]}]
      assert MemberRenewal.last_day(subscription(), paid, ~D[2026-03-10]) == ~D[2026-05-30]

      committed = subscription(%{commitment_ends_on: ~D[2026-12-31]})
      assert MemberRenewal.last_day(committed, [], ~D[2026-03-10]) == ~D[2026-12-31]
    end

    test "a subscription with its own end date keeps it" do
      fixed = subscription(%{ends_on: ~D[2026-02-15]})
      assert MemberRenewal.last_day(fixed, [], ~D[2026-02-01]) == ~D[2026-02-15]
    end

    test "without a recurring period it is today" do
      custom = subscription(%{billing_period_snapshot: "custom"})
      assert MemberRenewal.last_day(custom, [], ~D[2026-03-10]) == ~D[2026-03-10]
    end
  end

  describe "invoices after leaving" do
    test "only unpaid invoices for a period that begins after the last day go" do
      future = %{status: "issued", service_period_start: ~D[2026-04-01], paid_cents: 0}
      assert MemberRenewal.void_after_leaving?(future, ~D[2026-03-31])

      used = %{future | service_period_start: ~D[2026-03-01]}
      refute MemberRenewal.void_after_leaving?(used, ~D[2026-03-31])

      part_paid = %{future | paid_cents: 100}
      refute MemberRenewal.void_after_leaving?(part_paid, ~D[2026-03-31])

      paid = %{future | status: "paid"}
      refute MemberRenewal.void_after_leaving?(paid, ~D[2026-03-31])

      undated = %{future | service_period_start: nil}
      refute MemberRenewal.void_after_leaving?(undated, ~D[2026-03-31])
    end

    test "leaving day and staff limits" do
      assert MemberRenewal.leaving_on([], ~D[2026-03-10]) == ~D[2026-03-10]

      assert MemberRenewal.leaving_on([~D[2026-03-30], ~D[2026-05-01]], ~D[2026-03-10]) ==
               ~D[2026-05-01]

      assert {:error, :package_commitment_active} =
               MemberRenewal.staff_leaving_allowed(~D[2026-03-10], ~D[2026-12-31], nil)

      assert :ok = MemberRenewal.staff_leaving_allowed(~D[2026-03-10], ~D[2026-12-31], "Moved")
      assert :ok = MemberRenewal.staff_leaving_allowed(~D[2026-03-10], nil, nil)
    end

    test "a leave can be undone until the last day passes" do
      assert {:error, :not_leaving} =
               MemberRenewal.undo_allowed(%{leaving_on: nil}, ~D[2026-03-10])

      assert :ok = MemberRenewal.undo_allowed(%{leaving_on: ~D[2026-03-10]}, ~D[2026-03-10])

      assert {:error, :already_left} =
               MemberRenewal.undo_allowed(%{leaving_on: ~D[2026-03-09]}, ~D[2026-03-10])
    end
  end
end
