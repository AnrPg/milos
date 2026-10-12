defmodule MilosTrainingWeb.ClassTimerControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures, only: [slot_fixture: 2, workout_fixture: 2]

  alias MilosTraining.{Identity, Organizations}

  setup %{conn: conn} do
    admin = create_user!(:owner, "class_timer_coach")
    member = create_user!(:member, "class_timer_member")

    {:ok, context} =
      Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

    workout =
      workout_fixture(admin, %{
        tenant_context: context,
        sections: [
          %{
            name: "Tabata",
            order: 1,
            scoreable: false,
            timer_config: %{type: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 2},
            exercises: [
              %{name: "Burpee", order: 1, prescription_value: 10, prescription_unit: "reps"}
            ]
          }
        ]
      })

    slot = slot_fixture(workout, %{tenant_context: context})
    base = "/api/org/#{Organizations.legacy_organization_slug()}/class-timers/#{slot.id}"

    {:ok,
     coach: put_bearer_token(conn, admin),
     member: put_bearer_token(conn, member),
     base: base,
     slot: slot}
  end

  test "members can follow a class timer and see its sequence", %{member: member, base: base} do
    payload = member |> get(base) |> json_response(200)

    assert payload["timer"]["status"] == "ready"
    assert payload["timer"]["lock_version"] == 1
    assert length(payload["segments"]) == 3
    assert payload["class"]["name"]
    assert payload["server_now"]
  end

  test "coaches drive the timer; stale versions and members are refused", %{
    coach: coach,
    member: member,
    base: base,
    slot: slot
  } do
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "class_timer:updated")

    started =
      coach
      |> post("#{base}/commands", %{command: "start", countdown_seconds: 0, expected_version: 1})
      |> json_response(200)

    assert started["timer"]["status"] == "running"
    assert started["timer"]["lock_version"] == 2
    slot_id = slot.id
    assert_receive {:class_timer_updated, %{scheduled_class_id: ^slot_id}}

    assert %{"code" => "stale_class_timer"} =
             coach
             |> post("#{base}/commands", %{command: "pause", expected_version: 1})
             |> json_response(409)

    paused =
      coach
      |> post("#{base}/commands", %{command: "pause", expected_version: 2})
      |> json_response(200)

    assert paused["timer"]["status"] == "paused"

    assert %{"code" => "invalid_transition"} =
             coach
             |> post("#{base}/commands", %{command: "pause", expected_version: 3})
             |> json_response(422)

    member
    |> post("#{base}/commands", %{command: "resume", expected_version: 3})
    |> json_response(403)
  end

  test "a coach-chosen preset replaces the class workout's sequence until cleared", %{
    coach: coach,
    base: base
  } do
    configured =
      coach
      |> post("#{base}/commands", %{
        command: "configure",
        timer_preset: %{format: "amrap", duration_seconds: 600}
      })
      |> json_response(200)

    assert [%{"kind" => "countdown", "duration_seconds" => 600}] = configured["segments"]
    assert configured["timer"]["timer_preset"]["format"] == "amrap"

    cleared =
      coach
      |> post("#{base}/commands", %{command: "configure", timer_preset: nil})
      |> json_response(200)

    assert length(cleared["segments"]) == 3

    assert %{"code" => "invalid_command"} =
             coach
             |> post("#{base}/commands", %{command: "configure", timer_preset: %{format: "bogus"}})
             |> json_response(422)
  end

  defp create_user!(role, nickname) do
    {:ok, user} =
      Identity.register(%{
        nickname: "#{nickname}_#{System.unique_integer([:positive])}",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    user =
      if role == :owner do
        {:ok, admin} = Identity.update_role(user, :admin)
        admin
      else
        user
      end

    {:ok, _membership} =
      if role == :owner,
        do: Organizations.ensure_legacy_membership_for_migration(user, :owner),
        else: Organizations.ensure_legacy_membership_for_migration(user)

    user
  end
end
