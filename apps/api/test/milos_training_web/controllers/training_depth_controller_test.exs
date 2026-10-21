defmodule MilosTrainingWeb.TrainingDepthControllerTest do
  @moduledoc """
  ADR-165 over HTTP: `GET /api/me/progress/depth` (the caller's own data,
  Πρόοδος range and sources) and `GET /api/org/:slug/staff/clients/:id/
  progress-depth` (the client's own coach only, shared entries only).
  """

  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Execution.TrainingLogEntry
  alias MilosTraining.{Coaching, Organizations, Repo}

  setup %{conn: conn} do
    {:ok, gym} =
      Organizations.create_organization(%{name: "Depth Gym #{System.unique_integer()}"})

    owner = user_fixture()
    coach = user_fixture()
    other_coach = user_fixture()
    member = user_fixture()
    add!(gym, owner, :owner)
    add!(gym, coach, :coach)
    add!(gym, other_coach, :coach)
    add!(gym, member, :member)

    {:ok, _} =
      Coaching.start_relationship(%{organization_id: gym.id}, %{
        coach_user_id: coach.id,
        client_user_id: member.id,
        origin: "assigned"
      })

    %{
      conn: conn,
      gym: gym,
      owner: owner,
      coach: coach,
      other_coach: other_coach,
      member: member,
      staff: "/api/org/#{gym.slug}/staff"
    }
  end

  defp authed(ctx, user), do: ctx.conn |> recycle() |> put_bearer_token(user)

  defp log!(ctx, attrs) do
    Repo.insert!(
      struct(
        %TrainingLogEntry{
          user_id: ctx.member.id,
          organization_id: ctx.gym.id,
          source_type: "freeform",
          title: "Session",
          performed_at_utc: DateTime.utc_now(),
          idempotency_key: Ecto.UUID.generate(),
          performed_exercises: [%{"name" => "Back Squat", "sets" => 4}],
          perceived_effort: 6,
          duration_seconds: 3000
        },
        attrs
      )
    )
  end

  describe "GET /api/me/progress/depth" do
    test "the caller's coverage, qualities and load", ctx do
      log!(ctx, %{})

      body =
        authed(ctx, ctx.member)
        |> get("/api/me/progress/depth?range=4w&sources=#{ctx.gym.id}")
        |> json_response(200)

      assert body["range"] == "4w" and body["weeks"] == 4
      assert body["sources"] == [ctx.gym.id]
      assert body["coverage"]["sessions"] == 1
      assert %{"id" => "glutes", "sets" => 4.0} = hd(body["coverage"]["most"])
      assert length(body["qualities"]["qualities"]) == 10
      assert body["load"]["acute"] == 300
      assert body["load"]["sufficient"] == false and body["load"]["ratio"] == nil
      assert body["load"]["bands"] == %{"below" => 0.8, "steady_to" => 1.3, "above_to" => 1.5}
      assert length(body["load"]["weeks"]) == 8

      other = authed(ctx, ctx.owner) |> get("/api/me/progress/depth") |> json_response(200)
      assert other["range"] == "all" and other["coverage"]["sessions"] == 0
      assert other["coverage"]["least"] == []
    end

    test "rejects an unknown range and anonymous callers", ctx do
      assert authed(ctx, ctx.member)
             |> get("/api/me/progress/depth?range=2w")
             |> json_response(422)

      assert ctx.conn |> get("/api/me/progress/depth") |> json_response(401)
    end
  end

  describe "GET /api/org/:slug/staff/clients/:id/progress-depth" do
    test "the client's coach sees shared entries only; other coaches and members do not", ctx do
      log!(ctx, %{})
      log!(ctx, %{journal_visibility: "private", perceived_effort: 9, duration_seconds: 6000})
      path = "#{ctx.staff}/clients/#{ctx.member.id}/progress-depth"

      body = authed(ctx, ctx.coach) |> get(path) |> json_response(200)
      assert body["range"] == "4w"
      assert body["coverage"]["sessions"] == 1
      assert body["load"]["acute"] == 300
      refute Map.has_key?(body, "sources")

      assert authed(ctx, ctx.coach) |> get("#{path}?range=12w") |> json_response(200)
      assert authed(ctx, ctx.coach) |> get("#{path}?range=2w") |> json_response(422)
      assert authed(ctx, ctx.other_coach) |> get(path) |> json_response(403)
      assert authed(ctx, ctx.member) |> get(path) |> json_response(403)

      assert authed(ctx, ctx.coach)
             |> get("#{ctx.staff}/clients/#{Ecto.UUID.generate()}/progress-depth")
             |> json_response(404)
    end
  end

  defp add!(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        roles: if(role == :owner, do: [:owner, :coach], else: [role]),
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end
end
