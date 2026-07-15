defmodule MilosTraining.AdminDrillDownAlignmentTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Coaching.Domain.AthleteDrillDown
  alias MilosTraining.Finance.Domain.MemberDrillDown

  @today ~D[2026-06-13]

  test "finance and coaching current-state sections use aligned operator vocabulary" do
    finance =
      MemberDrillDown.build(
        %{id: "member-1", nickname: "maria", role: :member},
        %{membership: nil, package_subscriptions: [], payments: []},
        @today
      )

    coaching =
      AthleteDrillDown.build(
        %{id: "athlete-1", nickname: "eleni", role: :athlete},
        [
          %{
            id: "assignment-1",
            scheduled_for: "2026-06-20",
            workout: %{title: "Upcoming", type: "strength"}
          }
        ],
        [],
        [],
        @today
      )

    assert Map.take(finance.current_status, [:state, :reason, :urgency]) == %{
             state: "unmanaged",
             reason: "membership_profile_missing",
             urgency: "attention"
           }

    assert Map.take(coaching.recent_activity, [:state, :reason, :urgency]) == %{
             state: "drifting",
             reason: "assigned_without_completion",
             urgency: "attention"
           }
  end

  test "actions and attention items share the same contract shape" do
    finance =
      MemberDrillDown.build(
        %{id: "member-2", nickname: "nikos", role: :member},
        %{membership: nil, package_subscriptions: [], payments: []},
        @today
      )

    coaching =
      AthleteDrillDown.build(
        %{id: "athlete-2", nickname: "petros", role: :athlete},
        [
          %{
            id: "assignment-2",
            scheduled_for: "2026-06-01",
            workout: %{title: "Missed", type: "crossfit"}
          }
        ],
        [],
        [],
        @today
      )

    assert Enum.all?(finance.actions ++ coaching.actions, fn action ->
             Map.has_key?(action, :key) and
               Map.has_key?(action, :available) and
               Map.has_key?(action, :reason)
           end)

    assert Enum.all?(finance.outstanding_items ++ coaching.attention_cues, fn item ->
             Map.has_key?(item, :type) and
               Map.has_key?(item, :severity) and
               Map.has_key?(item, :reason) and
               Map.has_key?(item, :title)
           end)
  end
end
