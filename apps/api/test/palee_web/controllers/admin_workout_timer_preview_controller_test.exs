defmodule PaleeWeb.AdminWorkoutTimerPreviewControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Identity, Organizations}

  test "admin previews the exact segments a draft section will run", %{conn: conn} do
    {conn, organization} = authenticate(conn, "timer_preview_admin", :owner)

    response =
      conn
      |> post("/api/org/#{organization.slug}/admin/workouts/timer-preview", %{
        section: %{
          name: "Tabata",
          timer_config: %{type: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 3},
          exercises: [%{id: "bike", name: "Bike"}]
        }
      })
      |> json_response(200)

    assert Enum.map(response["segments"], & &1["label"]) ==
             ["Work 1/3", "Rest 1/3", "Work 2/3", "Rest 2/3", "Work 3/3"]

    assert response["total_seconds"] == 80
    assert response["open_ended"] == false
  end

  test "an invalid timer configuration is explained, not built", %{conn: conn} do
    {conn, organization} = authenticate(conn, "timer_preview_invalid", :owner)

    response =
      conn
      |> post("/api/org/#{organization.slug}/admin/workouts/timer-preview", %{
        section: %{timer_config: %{type: "hrr", hr_ceiling_bpm: 175}}
      })
      |> json_response(422)

    assert response["code"] == "invalid_timer_config"
    assert response["error"] =~ "effort_seconds"
  end

  test "members cannot use the authoring preview", %{conn: conn} do
    {conn, organization} = authenticate(conn, "timer_preview_member", :member)

    conn
    |> post("/api/org/#{organization.slug}/admin/workouts/timer-preview", %{
      section: %{timer_config: %{type: "amrap", duration_seconds: 600}}
    })
    |> json_response(403)
  end

  defp authenticate(conn, nickname, membership_role) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, user} =
      if membership_role == :owner, do: Identity.update_role(user, :admin), else: {:ok, user}

    {:ok, organization} = Organizations.create_organization(%{name: "#{nickname} Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: membership_role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {put_bearer_token(conn, user), organization}
  end
end
