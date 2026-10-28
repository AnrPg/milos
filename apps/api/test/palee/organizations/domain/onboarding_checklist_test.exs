defmodule Palee.Organizations.Domain.OnboardingChecklistTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.OnboardingChecklist

  @now ~U[2026-10-12 10:00:00Z]

  test "a new organization starts with every step open" do
    view = OnboardingChecklist.build(OnboardingChecklist.from_settings(%{}), %{})

    assert view["completed_count"] == 0
    assert view["total"] == 8
    refute view["finished"]
    refute view["dismissed"]

    assert Enum.map(view["steps"], & &1["id"]) ==
             ~w(timezone settings classes packages workout page invite tour)
  end

  test "real data completes steps automatically" do
    view =
      OnboardingChecklist.build(OnboardingChecklist.default_state(), %{
        "packages" => true,
        "invite" => true
      })

    assert %{"done" => true, "auto" => true} = Enum.find(view["steps"], &(&1["id"] == "packages"))
    assert view["completed_count"] == 2
  end

  test "admins complete, skip and reopen steps; finishing needs every step resolved" do
    state = OnboardingChecklist.default_state()

    state =
      Enum.reduce(~w(timezone settings classes packages workout page invite), state, fn step,
                                                                                        acc ->
        {:ok, next} =
          OnboardingChecklist.apply_action(acc, %{"action" => "complete", "step" => step}, @now)

        next
      end)

    refute OnboardingChecklist.build(state, %{})["finished"]

    {:ok, state} = OnboardingChecklist.apply_action(state, %{action: "skip", step: "tour"}, @now)
    assert OnboardingChecklist.build(state, %{})["finished"]

    {:ok, state} =
      OnboardingChecklist.apply_action(state, %{"action" => "reopen", "step" => "tour"}, @now)

    refute OnboardingChecklist.build(state, %{})["finished"]
  end

  test "finishing the tour completes its step" do
    {:ok, state} =
      OnboardingChecklist.apply_action(
        OnboardingChecklist.default_state(),
        %{"action" => "tour_completed"},
        @now
      )

    view = OnboardingChecklist.build(state, %{})
    assert view["tour_completed"]
    assert %{"done" => true} = Enum.find(view["steps"], &(&1["id"] == "tour"))
  end

  test "dismissing hides the popup until restored" do
    {:ok, state} =
      OnboardingChecklist.apply_action(
        OnboardingChecklist.default_state(),
        %{"action" => "dismiss"},
        @now
      )

    assert OnboardingChecklist.build(state, %{})["dismissed"]

    {:ok, state} = OnboardingChecklist.apply_action(state, %{"action" => "restore"}, @now)
    refute OnboardingChecklist.build(state, %{})["dismissed"]
  end

  test "rejects unknown actions and steps, and ignores unknown stored steps" do
    state = OnboardingChecklist.default_state()

    assert {:error, :invalid_onboarding_action} =
             OnboardingChecklist.apply_action(state, %{"action" => "nuke"}, @now)

    assert {:error, :invalid_onboarding_action} =
             OnboardingChecklist.apply_action(
               state,
               %{"action" => "complete", "step" => "x"},
               @now
             )

    stored = %{
      "onboarding" => %{"completed" => ["x", "settings", "settings"], "dismissed_at" => 5}
    }

    assert %{"completed" => ["settings"], "dismissed_at" => nil} =
             OnboardingChecklist.from_settings(stored)
  end

  test "an independent coach gets the practice steps (ADR-170)" do
    state = OnboardingChecklist.default_state()

    view =
      OnboardingChecklist.build(state, %{"sessions" => true, "classes" => true}, "coach")

    assert view["audience"] == "coach"

    assert ~w(timezone profile sessions packages team bootcamp invite tour) ==
             Enum.map(view["steps"], & &1["id"])

    assert %{"done" => true, "auto" => true} = Enum.find(view["steps"], &(&1["id"] == "sessions"))
    assert view["total"] == 8

    assert {:ok, %{"completed" => ["team"]}} =
             OnboardingChecklist.apply_action(
               state,
               %{"action" => "complete", "step" => "team"},
               @now,
               "coach"
             )

    # A gym step is not a coach step, and the other way round.
    assert {:error, :invalid_onboarding_action} =
             OnboardingChecklist.apply_action(
               state,
               %{"action" => "skip", "step" => "classes"},
               @now,
               "coach"
             )

    assert {:error, :invalid_onboarding_action} =
             OnboardingChecklist.apply_action(
               state,
               %{"action" => "skip", "step" => "team"},
               @now
             )

    assert "gym" == OnboardingChecklist.audience("anything else")
  end
end
