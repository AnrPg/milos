defmodule MilosTrainingWeb.AnatomyAtlasControllerTest do
  @moduledoc """
  ADR-164 over HTTP: `GET /api/me/atlas` (authenticated, the caller's own
  data, range validation) and `GET /api/org/:slug/anatomy/nodes/:id/exercises`
  (members of the gym only, unknown nodes 404, videos only when the package
  includes on-demand videos).
  """

  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Content.Video
  alias MilosTraining.Execution.WorkoutExecution
  alias MilosTraining.{Finance, Organizations, Repo}

  setup %{conn: conn} do
    {:ok, gym} =
      Organizations.create_organization(%{name: "Atlas Gym #{System.unique_integer()}"})

    owner = user_fixture()
    member = user_fixture()
    add!(gym, owner, :owner)
    add!(gym, member, :member)
    {:ok, staff} = Organizations.resolve_tenant_context(owner, gym.slug)
    workout = workout_fixture(owner, %{tenant_context: staff})

    %{conn: conn, gym: gym, owner: owner, member: member, workout: workout}
  end

  defp authed(ctx, user), do: ctx.conn |> recycle() |> put_bearer_token(user)

  describe "GET /api/me/atlas" do
    test "the caller's coverage, 4 weeks by default", ctx do
      Repo.insert!(%WorkoutExecution{
        user_id: ctx.member.id,
        organization_id: ctx.gym.id,
        master_workout_id: ctx.workout.id,
        status: :completed,
        started_at_utc: DateTime.utc_now(),
        completed_at_utc: DateTime.utc_now()
      })

      body = authed(ctx, ctx.member) |> get("/api/me/atlas") |> json_response(200)

      assert body["range"] == "4w" and body["weeks"] == 4
      assert body["sessions"] == 1
      assert body["thresholds"] == %{"medium" => 3.0, "high" => 8.0}

      quads = Enum.find(body["nodes"], &(&1["id"] == "quadriceps"))
      # The fixture's Air Squats: 3 sets, quadriceps primary.
      assert %{"sets" => 3.0, "level" => "low", "kind" => "group", "felt" => 0} = quads
      assert [%{"exercise_ref" => "air-squat", "sets" => 3.0}] = quads["top_exercises"]

      # Someone else sees none of it.
      other = authed(ctx, ctx.owner) |> get("/api/me/atlas?range=12w") |> json_response(200)
      assert other["range"] == "12w" and other["sessions"] == 0 and other["nodes"] == []
    end

    test "rejects an unknown range and anonymous callers", ctx do
      assert authed(ctx, ctx.member) |> get("/api/me/atlas?range=6m") |> json_response(422)
      assert ctx.conn |> get("/api/me/atlas") |> json_response(401)
    end
  end

  describe "GET /api/org/:slug/anatomy/nodes/:node_id/exercises" do
    test "members get the exercises of a node; strangers and unknown nodes do not", ctx do
      base = "/api/org/#{ctx.gym.slug}/anatomy/nodes"

      body = authed(ctx, ctx.member) |> get("#{base}/quadriceps/exercises") |> json_response(200)
      assert body["node_id"] == "quadriceps"

      assert Enum.any?(
               body["exercises"],
               &(&1["exercise_ref"] == "back-squat" and &1["role"] == "primary")
             )

      assert authed(ctx, ctx.member) |> get("#{base}/spleen/exercises") |> json_response(404)

      stranger = user_fixture()
      # Not a member: the gym does not resolve for them.
      assert authed(ctx, stranger) |> get("#{base}/quadriceps/exercises") |> json_response(404)
      assert ctx.conn |> get("#{base}/quadriceps/exercises") |> json_response(401)
    end
  end

  describe "videos follow the on-demand package gate" do
    setup do
      {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
      Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

      {:ok, _settings} =
        Finance.update_finance_settings(%{
          entitlement_enforcement_mode: "enforce_managed",
          entitlement_timezone: "Europe/Athens",
          payment_reminder_interval_days: 7
        })

      Repo.insert!(%Video{
        organization_id: organization.id,
        title: "Back squat",
        video_url: "https://videos.example/back-squat",
        tags: ["strength"],
        published_at: DateTime.utc_now()
      })

      %{base: "/api/org/#{Organizations.legacy_organization_slug()}/anatomy/nodes"}
    end

    test "with the benefit the videos come along; without it only the exercises", ctx do
      viewer = client(ctx.conn, %{"content.on_demand_video" => true})
      body = viewer |> get("#{ctx.base}/quadriceps/exercises") |> json_response(200)
      assert body["videos_included"] == true
      squat = Enum.find(body["exercises"], &(&1["exercise_ref"] == "back-squat"))

      assert [%{"title" => "Back squat", "video_url" => "https://videos.example/back-squat"}] =
               squat["videos"]

      # An exercise with a video leads its role.
      assert hd(body["exercises"])["exercise_ref"] == "back-squat"

      plain = client(ctx.conn, %{})
      body = plain |> get("#{ctx.base}/quadriceps/exercises") |> json_response(200)
      assert body["videos_included"] == false
      assert Enum.all?(body["exercises"], &(&1["videos"] == []))
    end
  end

  defp client(conn, fields) do
    user = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user)

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, package} =
      Finance.create_package(%{
        name: "Content #{System.unique_integer([:positive])}",
        package_type: "membership",
        fields: fields
      })

    {:ok, _} = Finance.assign_package(membership.id, package.id, %{})
    conn |> recycle() |> put_bearer_token(user)
  end

  defp add!(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        roles: if(role == :owner, do: [:owner, :coach], else: [role]),
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
