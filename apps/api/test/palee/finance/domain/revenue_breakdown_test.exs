defmodule Palee.Finance.Domain.RevenueBreakdownTest do
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.RevenueBreakdown

  describe "classify/1" do
    test "an explicit stream wins over everything else" do
      assert RevenueBreakdown.classify(%{explicit_stream: "shop", package_type: "membership"}) ==
               "shop"
    end

    test "the column default is refined, never taken as is" do
      assert RevenueBreakdown.classify(%{explicit_stream: "membership", package_type: "drop_in"}) ==
               "package"

      assert RevenueBreakdown.classify(%{
               explicit_stream: "membership",
               reference: "community_event_attendee:1"
             }) == "event"

      assert RevenueBreakdown.classify(%{explicit_stream: "membership"}) == "other"
      assert RevenueBreakdown.classify(%{explicit_stream: "event"}) == "event"
    end

    test "an unknown explicit stream is ignored" do
      assert RevenueBreakdown.classify(%{explicit_stream: "crypto", package_type: "class_pack"}) ==
               "package"
    end

    test "recurring package types are memberships, one-off types are packages" do
      for type <- ~w(membership shared corporate),
          do: assert(RevenueBreakdown.classify(%{package_type: type}) == "membership")

      for type <- ~w(class_pack drop_in trial pt_pack add_on),
          do: assert(RevenueBreakdown.classify(%{package_type: type}) == "package")
    end

    test "event receipts are events" do
      assert RevenueBreakdown.classify(%{reference: "community_event_attendee:abc"}) == "event"
      assert RevenueBreakdown.classify(%{charge_category: "event"}) == "event"
    end

    test "anything else is other" do
      assert RevenueBreakdown.classify(%{}) == "other"

      assert RevenueBreakdown.classify(%{reference: "manual", charge_category: "product"}) ==
               "other"
    end
  end

  describe "breakdown/1" do
    test "every stream is present and the nets add up to the groups' net" do
      groups = [
        {%{package_type: "membership"}, 10_000, 7_000, 2},
        {%{package_type: "class_pack"}, 5_000, 5_000, 1},
        {%{explicit_stream: "shop"}, 3_000, 2_500, 3},
        {%{explicit_stream: "shop"}, 1_000, 1_000, 1}
      ]

      %{rows: rows, net_by_stream: net} = RevenueBreakdown.breakdown(groups)

      assert Enum.map(rows, & &1.stream) == RevenueBreakdown.all()

      assert net == %{
               "membership" => 7_000,
               "package" => 5_000,
               "event" => 0,
               "shop" => 3_500,
               "other" => 0
             }

      assert Enum.sum(Map.values(net)) == 7_000 + 5_000 + 2_500 + 1_000

      assert Enum.find(rows, &(&1.stream == "shop")) == %{
               stream: "shop",
               gross_cents: 4_000,
               refunded_cents: 500,
               net_cents: 3_500,
               payment_count: 4
             }
    end
  end
end
