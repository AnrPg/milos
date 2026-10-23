defmodule Palee.Finance.Domain.MemberOffersTest do
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.MemberOffers

  @today ~D[2026-10-23]

  defp campaign(attrs) do
    Map.merge(
      %{
        id: "c1",
        name: "Autumn",
        description: nil,
        active: true,
        starts_on: nil,
        ends_on: nil,
        params: %{"member_visible" => true}
      },
      attrs
    )
  end

  defp code(attrs) do
    Map.merge(
      %{
        id: "k1",
        promotion_campaign_id: "c1",
        code: "AUTUMN10",
        discount_type: "percent",
        discount_value: 10,
        active: true
      },
      attrs
    )
  end

  test "only flagged, active campaigns running today are shown" do
    assert MemberOffers.visible?(campaign(%{}), @today)
    refute MemberOffers.visible?(campaign(%{params: %{}}), @today)
    refute MemberOffers.visible?(campaign(%{active: false}), @today)
    refute MemberOffers.visible?(campaign(%{starts_on: ~D[2026-10-24]}), @today)
    refute MemberOffers.visible?(campaign(%{ends_on: ~D[2026-10-22]}), @today)
    assert MemberOffers.visible?(campaign(%{starts_on: @today, ends_on: @today}), @today)
  end

  test "one offer per active code of a shown campaign" do
    campaigns = [campaign(%{}), campaign(%{id: "c2", params: %{}})]

    codes = [
      code(%{}),
      code(%{id: "k2", code: "OFF", active: false}),
      code(%{id: "k3", promotion_campaign_id: "c2", code: "HIDDEN"})
    ]

    assert [%{id: "k1", code: "AUTUMN10", campaign_name: "Autumn", discount_value: 10}] =
             MemberOffers.available(campaigns, codes, @today)
  end
end
