defmodule PaleeWeb.ClassTimerPlanTest do
  @moduledoc "ADR-270: a class running a structured plan WOD times it from its plan and shows its plan body."
  use PaleeWeb.ConnCase, async: false

  import Palee.StructuredPlanFixtures
  import Palee.TestFixtures, only: [slot_fixture: 2, workout_fixture: 2]

  alias Palee.{Identity, Organizations}

  test "the wall display gets one plan segment per section and the plan body", %{conn: conn} do
    {:ok, user} =
      Identity.register(%{
        nickname: "plan_timer_coach",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, admin} = Identity.update_role(user, :admin)
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)

    {:ok, context} =
      Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

    workout =
      workout_fixture(admin, %{
        tenant_context: context,
        authoring_mode: "structured_plan",
        sections: [
          %{name: "Engine", order: 1, plan: Enum.at(program(), 7)},
          %{
            name: "EMOM",
            order: 2,
            plan:
              section("emom", %{"every" => "1:00", "times" => "10"}, [[ex("e", "Burpee", "10")]])
          }
        ]
      })

    slot = slot_fixture(workout, %{tenant_context: context})

    payload =
      conn
      |> put_bearer_token(admin)
      |> get("/api/org/#{Organizations.legacy_organization_slug()}/class-timers/#{slot.id}")
      |> json_response(200)

    assert [
             %{"format" => "structured_plan", "kind" => "countup", "scoreable" => true},
             %{"kind" => "interval_cycle", "duration_seconds" => 60, "total_rounds" => 10}
           ] = payload["segments"]

    assert %{
             "authoring_mode" => "structured_plan",
             "body" => %{"kind" => "plan", "sections" => [engine, _emom]}
           } =
             payload["workout"]

    assert %{
             "name" => "Engine",
             "plan" => %{"flow" => "for_time"},
             "prescription" => %{"clock" => _}
           } =
             engine
  end
end
