defmodule MilosTraining.Finance.Domain.PackagePhaseCPlanTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.{EntitlementPlan, EntitlementPolicy}

  defp plan(type, fields) do
    {:ok, plan} =
      EntitlementPlan.parse(%{
        "entitlement_version" => 2,
        "package_type" => type,
        "fields" => fields
      })

    plan
  end

  test "Phase C fields compile into channels, capabilities and allowances" do
    pt =
      plan("pt_pack", %{
        "personal_training.sessions" => %{"limit" => 8, "period" => "subscription_period"},
        "personal_training.assessments" => 2,
        "personal_training.format" => "semi_private",
        "online_coaching.form_reviews" => %{"limit" => 3, "period" => "calendar_month"},
        "online_coaching.nutrition_plan" => true,
        "content.on_demand_video" => true,
        "content.advanced_analytics" => true
      })

    assert MapSet.subset?(
             MapSet.new([:personal_training, :digital_content, :nutrition]),
             pt.channels
           )

    for capability <- [
          :book_pt_sessions,
          :book_assessments,
          :request_form_reviews,
          :receive_nutrition_plan,
          :watch_on_demand,
          :view_advanced_analytics
        ] do
      assert MapSet.member?(pt.capabilities, capability)
    end

    assert %{limit: 8, period: :subscription_period} = pt.allowances.pt_sessions
    assert %{limit: 2, period: :subscription_period} = pt.allowances.assessments
    assert %{limit: 3, period: :calendar_month} = pt.allowances.form_reviews
    assert pt.terms.pt_format == "semi_private"
    refute MapSet.member?(pt.capabilities, :book_classes)
  end

  test "serialized plans parse back unchanged instead of falling back to a preset" do
    original =
      plan("pt_pack", %{
        "group_classes.included" => false,
        "personal_training.sessions" => %{"limit" => 5, "period" => "subscription_period"}
      })

    json = original |> EntitlementPlan.serialize() |> Jason.encode!() |> Jason.decode!()
    assert {:ok, parsed} = EntitlementPlan.parse(json)

    assert parsed.channels == original.channels
    assert parsed.capabilities == original.capabilities
    assert parsed.allowances.pt_sessions.limit == 5
    assert parsed.terms.pt_format == original.terms.pt_format

    # A PT-only member must not pass a group-class check through the read model.
    entitlement = %{status: "active", plan: json}

    assert {:error, _reason} =
             EntitlementPolicy.authorize(
               entitlement,
               %{channel: :in_person, capability: :book_classes},
               mode: :enforce_all
             )
  end

  test "merging grants the union of access and keeps the primary's terms" do
    membership =
      plan("membership", %{
        "group_classes.class_types" => [Ecto.UUID.generate()],
        "booking.waitlist_priority" => "high"
      })

    add_on =
      plan("add_on", %{"content.on_demand_video" => true, "group_classes.included" => false})

    merged = EntitlementPlan.merge([membership, add_on])

    assert MapSet.member?(merged.capabilities, :book_classes)
    assert MapSet.member?(merged.capabilities, :watch_on_demand)
    assert merged.terms.waitlist_priority == "high"
    refute MapSet.member?(merged.capabilities, :execute_library_workouts)
    assert EntitlementPlan.merge([membership]) == membership
    assert EntitlementPlan.merge([]) == nil
  end
end
