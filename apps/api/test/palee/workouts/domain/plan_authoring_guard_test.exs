defmodule Palee.Workouts.Domain.PlanAuthoringGuardTest do
  @moduledoc "ADR-270: a legacy editor's save never silently drops a structured plan."
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.PlanAuthoringGuard

  @plan_workout %{authoring_mode: "structured_plan", sections: [%{plan: %{"flow" => "sets"}}]}

  test "Quick Text never replaces a plan workout" do
    assert {:error, :structured_plan_mode_change} =
             PlanAuthoringGuard.check_quick_text(@plan_workout)

    # A draft of a plan workout carries its mode in the draft data.
    draft = %{authoring_mode: nil, draft_data: %{"authoring_mode" => "structured_plan"}}
    assert {:error, :structured_plan_mode_change} = PlanAuthoringGuard.check_quick_text(draft)

    assert :ok = PlanAuthoringGuard.check_quick_text(%{authoring_mode: "structured"})
    assert :ok = PlanAuthoringGuard.check_quick_text(nil)
  end

  test "a save over a plan workout keeps it a plan or switches to text on purpose" do
    check = &PlanAuthoringGuard.check_save(@plan_workout, &1)

    assert :ok = check.(%{"authoring_mode" => "structured_plan", "sections" => []})
    assert :ok = check.(%{authoring_mode: "free_text", free_text_body: "AMRAP 12"})
    assert :ok = check.(%{"authoring_mode" => "sectioned_text"})
    assert :ok = check.(%{"title" => "Renamed"})
    assert :ok = check.(%{"sections" => [%{"plan" => %{"flow" => "sets"}}]})

    assert {:error, :structured_plan_mode_change} = check.(%{"authoring_mode" => "quick_text"})
    assert {:error, :structured_plan_mode_change} = check.(%{authoring_mode: :structured})

    assert {:error, :structured_plan_mode_change} =
             check.(%{"sections" => [%{"name" => "Main", "exercises" => []}]})
  end

  test "a draft save is checked on its draft data and top-level mode" do
    check = &PlanAuthoringGuard.check_draft_save(@plan_workout, &1)
    draft = %{authoring_mode: nil, draft_data: %{"authoring_mode" => "structured_plan"}}

    assert :ok = check.(%{draft_data: %{"authoring_mode" => "structured_plan", "sections" => []}})
    assert :ok = check.(%{"draft_data" => %{"title" => "Renamed"}})
    assert :ok = check.(%{draft_data: %{"title" => "Text"}, authoring_mode: "free_text"})
    assert :ok = check.(%{"authoring_mode" => "sectioned_text", "sections" => []})

    assert {:error, :structured_plan_mode_change} =
             check.(%{draft_data: %{"authoring_mode" => "structured", "sections" => []}})

    assert {:error, :structured_plan_mode_change} =
             PlanAuthoringGuard.check_draft_save(draft, %{
               draft_data: %{"authoring_mode" => "structured_plan"},
               authoring_mode: "quick_text"
             })

    assert {:error, :structured_plan_mode_change} =
             check.(%{draft_data: %{"sections" => [%{"name" => "Main", "exercises" => []}]}})

    assert :ok =
             PlanAuthoringGuard.check_draft_save(%{authoring_mode: "structured"}, %{
               draft_data: %{"authoring_mode" => "quick_text"}
             })
  end

  test "other workouts save as before" do
    assert :ok =
             PlanAuthoringGuard.check_save(%{authoring_mode: "structured"}, %{
               "authoring_mode" => "quick_text"
             })

    assert :ok = PlanAuthoringGuard.check_save(nil, %{})
  end
end
