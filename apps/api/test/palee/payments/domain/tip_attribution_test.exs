defmodule Palee.Payments.Domain.TipAttributionTest do
  use ExUnit.Case, async: true

  alias Palee.Payments.Domain.TipAttribution

  @starter "00000000-0000-0000-0000-000000000001"
  @desk_a "00000000-0000-0000-0000-00000000000a"
  @desk_b "00000000-0000-0000-0000-00000000000b"
  @owner "00000000-0000-0000-0000-0000000000ff"

  defp intent(attrs),
    do:
      Map.merge(
        %{tip_cents: 200, tip_attribution: nil, created_by_id: @starter, metadata: %{}},
        attrs
      )

  test "no tip, or a tip already attributed: nothing to write" do
    assert TipAttribution.attribute(intent(%{tip_cents: 0}), %{}) == nil
    assert TipAttribution.attribute(intent(%{tip_attribution: "started_payment"}), %{}) == nil
  end

  test "started on a phone: the person who started it" do
    assert TipAttribution.attribute(intent(%{}), %{@desk_a => [:front_desk]}) ==
             %{tip_attribution: "started_payment", tip_recipient_user_id: @starter}
  end

  test "started at the desk: the only front desk person, owners and admins never counted" do
    desk = intent(%{metadata: %{"started_on" => "desk"}})

    roles = %{
      @desk_a => [:front_desk],
      @owner => [:owner, :front_desk],
      "x" => [:admin, "front_desk"]
    }

    assert TipAttribution.attribute(desk, roles) ==
             %{tip_attribution: "sole_front_desk", tip_recipient_user_id: @desk_a}
  end

  test "several or no front desk people: the front desk role, unpersonalised" do
    desk = intent(%{metadata: %{"started_on" => "desk"}})
    role = %{tip_attribution: "front_desk_role", tip_recipient_role: "front_desk"}

    assert TipAttribution.attribute(desk, %{@desk_a => [:front_desk], @desk_b => ["front_desk"]}) ==
             role

    assert TipAttribution.attribute(desk, %{@owner => [:owner, :front_desk]}) == role
  end

  test "with no starter on record the workflow decides" do
    assert TipAttribution.attribute(intent(%{created_by_id: nil}), %{@desk_a => [:front_desk]}) ==
             %{tip_attribution: "sole_front_desk", tip_recipient_user_id: @desk_a}
  end

  test "where a payment started" do
    assert TipAttribution.started_on(intent(%{})) == "phone"
    assert TipAttribution.started_on(intent(%{metadata: %{"started_on" => "desk"}})) == "desk"
    assert TipAttribution.started_on(%{}) == "phone"
  end
end
