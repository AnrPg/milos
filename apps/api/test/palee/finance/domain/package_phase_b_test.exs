defmodule Palee.Finance.Domain.PackagePhaseBTest do
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.{
    AllowancePeriod,
    EntitlementPlan,
    EntitlementPolicy,
    PackageContract,
    SubscriptionTerms
  }

  @location_a "33333333-3333-4333-8333-333333333333"
  @location_b "44444444-4444-4444-8444-444444444444"

  defp plan(fields, type \\ "membership") do
    {:ok, contract} = PackageContract.normalize(%{"package_type" => type, "fields" => fields})
    params = PackageContract.to_params(contract)
    {:ok, plan} = EntitlementPlan.parse(params)
    {plan, %{status: "active", plan: params}}
  end

  test "Phase B fields are authorable" do
    assert {:ok, %{fields: fields}} =
             PackageContract.normalize(%{
               "package_type" => "membership",
               "fields" => %{
                 "perks.guest_passes" => %{"limit" => 2, "period" => "calendar_month"},
                 "perks.freeze_days_per_year" => 14,
                 "booking.window_days" => 7,
                 "booking.waitlist_priority" => "high"
               }
             })

    assert fields["perks.guest_passes"]["limit"] == 2
    assert fields["booking.window_days"] == 7

    assert {:error, {:package_rule_violated, :discount_scope_required, _}} =
             PackageContract.normalize(%{
               "package_type" => "membership",
               "fields" => %{"perks.member_discount_percent" => 10}
             })
  end

  test "events, guests and open gym compile into their own access" do
    {plan, _} =
      plan(%{
        "perks.events" => true,
        "perks.guest_passes" => %{"limit" => 2, "period" => "calendar_month"},
        "facility.open_gym" => true
      })

    assert MapSet.subset?(MapSet.new([:events, :facility, :in_person]), plan.channels)
    assert MapSet.subset?(MapSet.new([:book_events, :bring_guests, :open_gym]), plan.capabilities)
    assert plan.allowances.guest_passes.limit == 2
    assert plan.allowances.event_visits.limit == :unlimited

    {plain, _} = plan(%{})
    refute MapSet.member?(plain.capabilities, :bring_guests)
  end

  test "time windows and locations are enforced for group classes" do
    windows = [%{"days" => [1, 2, 3, 4, 5], "from" => "06:00", "to" => "12:00"}]

    {_plan, entitlement} =
      plan(%{"group_classes.time_windows" => windows, "facility.location_ids" => [@location_a]})

    request = %{channel: :in_person, capability: :book_classes}

    assert {:ok, _} =
             EntitlementPolicy.authorize(
               entitlement,
               Map.merge(request, %{
                 local_weekday: 2,
                 local_time: ~T[07:00:00],
                 location_id: @location_a
               }),
               mode: :enforce_all
             )

    assert {:error, :finance_time_window_not_included} =
             EntitlementPolicy.authorize(
               entitlement,
               Map.merge(request, %{local_weekday: 6, local_time: ~T[07:00:00]}),
               mode: :enforce_all
             )

    assert {:error, :finance_location_not_included} =
             EntitlementPolicy.authorize(
               entitlement,
               Map.merge(request, %{
                 local_weekday: 2,
                 local_time: ~T[08:00:00],
                 location_id: @location_b
               }),
               mode: :enforce_all
             )
  end

  test "terms expose booking privileges and commercial terms" do
    {plan, _} =
      plan(%{
        "booking.cancellation_cutoff_hours" => 12,
        "booking.no_show_penalty_waived" => true,
        "group_classes.visits" => %{"limit" => 8, "period" => "calendar_month"},
        "group_classes.rollover_max" => 2
      })

    assert plan.terms.cancellation_cutoff_hours == 12
    assert plan.terms.no_show_penalty_waived
    assert plan.terms.rollover_max == 2
    assert plan.terms.waitlist_priority == "normal"
  end

  test "commitment, activation and freezes" do
    assert SubscriptionTerms.commitment_ends_on(~D[2026-01-15], 12) == ~D[2027-01-14]
    assert SubscriptionTerms.commitment_ends_on(~D[2026-01-15], 0) == nil

    assert {:error, :package_commitment_active} =
             SubscriptionTerms.cancellation_allowed?(~D[2027-01-14], ~D[2026-06-01], nil)

    assert :ok =
             SubscriptionTerms.cancellation_allowed?(
               ~D[2027-01-14],
               ~D[2026-06-01],
               "Moving abroad"
             )

    assert :ok = SubscriptionTerms.cancellation_allowed?(~D[2026-01-14], ~D[2026-06-01], nil)

    assert SubscriptionTerms.activation_ends_on(~D[2026-03-10], %{
             "amount" => 1,
             "unit" => "month"
           }) ==
             ~D[2026-04-09]

    used = [{~D[2026-02-01], ~D[2026-02-10]}]

    assert {:ok, %{days: 5, remaining: 15}} =
             SubscriptionTerms.validate_freeze(
               ~D[2026-03-01],
               ~D[2026-03-05],
               30,
               used,
               ~D[2026-02-20]
             )

    assert {:error, :freeze_allowance_exceeded} =
             SubscriptionTerms.validate_freeze(
               ~D[2026-03-01],
               ~D[2026-03-25],
               30,
               used,
               ~D[2026-02-20]
             )

    assert {:error, :freeze_overlaps} =
             SubscriptionTerms.validate_freeze(
               ~D[2026-02-05],
               ~D[2026-02-06],
               30,
               used,
               ~D[2026-02-01]
             )

    assert {:error, :freeze_not_included} =
             SubscriptionTerms.validate_freeze(
               ~D[2026-03-01],
               ~D[2026-03-02],
               0,
               [],
               ~D[2026-02-20]
             )

    assert SubscriptionTerms.frozen_on?(used, ~D[2026-02-10])
    refute SubscriptionTerms.frozen_on?(used, ~D[2026-02-11])
  end

  test "rollover carries at most the configured units from the previous period" do
    assert SubscriptionTerms.carry_over(8, 0, 5, 2) == 2
    assert SubscriptionTerms.carry_over(8, 1, 8, 2) == 1
    assert SubscriptionTerms.carry_over(8, 0, 9, 2) == 0
    assert SubscriptionTerms.carry_over(:unlimited, 0, 0, 2) == 0
    assert SubscriptionTerms.carry_over(8, 0, 0, 0) == 0

    assert AllowancePeriod.previous_bounds(:calendar_month, ~D[2026-03-15]) ==
             {~D[2026-02-01], ~D[2026-02-28]}

    assert AllowancePeriod.previous_bounds(:calendar_week, ~D[2026-03-04]) ==
             {~D[2026-02-23], ~D[2026-03-01]}

    assert AllowancePeriod.previous_bounds(:subscription_period, ~D[2026-03-04]) == nil
  end

  test "member discounts apply only to manual charges in scope" do
    lines = [
      %{
        "line_type" => "manual_charge",
        "charge_category" => "product",
        "quantity" => 2,
        "unit_amount_cents" => 1000
      },
      %{
        "line_type" => "manual_charge",
        "charge_category" => "other",
        "quantity" => 1,
        "unit_amount_cents" => 500
      },
      %{"line_type" => "membership_package", "quantity" => 1, "unit_amount_cents" => 6000}
    ]

    [product, other, package] = SubscriptionTerms.apply_member_discount(lines, 10, ["products"])
    assert product["discount_cents"] == 200
    refute Map.has_key?(other, "member_discount_percent")
    assert package == Enum.at(lines, 2)
    assert SubscriptionTerms.apply_member_discount(lines, 0, ["products"]) == lines
  end
end
