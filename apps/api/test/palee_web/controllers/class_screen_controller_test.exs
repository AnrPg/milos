defmodule PaleeWeb.ClassScreenControllerTest do
  @moduledoc """
  ADR-253 update 2026-10-29 over HTTP: «Στην οθόνη» on a class timer's
  remote. The class's own coach pins its timer, leaderboard or WOD on a
  screen of the class's branch or the whole box, today, and returns it to
  automatic; a coach of another class, a coach on another branch's screen,
  a class of another day and members are refused; owners keep their rights.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Facility, Organizations, Repo}
  alias Palee.TestSupport.{BoxScreenFixtures, FixedBoxScreenClock}

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    staff = fn role ->
      user = if role == :owner, do: admin_fixture(), else: user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      {user, put_bearer_token(conn, user)}
    end

    {owner_user, owner} = staff.(:owner)
    {coach_user, coach} = staff.(:coach)
    {_other_coach_user, other_coach} = staff.(:coach)
    {_member_user, member} = staff.(:member)

    {:ok, context} =
      Organizations.resolve_tenant_context(owner_user, Organizations.legacy_organization_slug())

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    FixedBoxScreenClock.put(now)
    BoxScreenFixtures.set_gym_zone!(organization.id, BoxScreenFixtures.midday_zone(now))

    {:ok, branch} = Facility.create_location(context, %{name: "Κυψέλη"})
    {:ok, other_branch} = Facility.create_location(context, %{name: "Παγκράτι"})

    slug = Organizations.legacy_organization_slug()

    %{
      context: context,
      owner_user: owner_user,
      owner: owner,
      coach_user: coach_user,
      coach: coach,
      other_coach: other_coach,
      member: member,
      now: now,
      branch: branch,
      other_branch: other_branch,
      admin: "/api/org/#{slug}/admin/box-screens",
      timers: "/api/org/#{slug}/class-timers"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp get_json(conn, path), do: conn |> recycle() |> get(path)

  defp class(ctx, coach_user_id, location_id, at) do
    slot = ctx.owner_user |> workout_fixture() |> slot_fixture()

    Repo.query!(
      "UPDATE scheduled_classes SET scheduled_at = $1, coach_user_id = $2, location_id = $3 WHERE id = $4",
      [at, dump(coach_user_id), dump(location_id), Ecto.UUID.dump!(slot.id)]
    )

    slot.id
  end

  defp dump(nil), do: nil
  defp dump(id), do: Ecto.UUID.dump!(id)

  defp screen(ctx, name, location_id) do
    %{"screen" => %{"id" => id}} =
      ctx.owner
      |> send_json(:post, ctx.admin, %{name: name, location_id: location_id})
      |> json_response(201)

    id
  end

  test "the class's coach pins its timer, leaderboard or WOD and returns to automatic", ctx do
    slot_id = class(ctx, ctx.coach_user.id, ctx.branch.id, DateTime.add(ctx.now, 600))
    room = screen(ctx, "Αίθουσα", ctx.branch.id)
    whole = screen(ctx, "Είσοδος", nil)
    _elsewhere = screen(ctx, "Παγκράτι TV", ctx.other_branch.id)

    assert %{"screens" => screens, "views" => ["timer", "leaderboard", "wod"]} =
             ctx.coach |> get_json("#{ctx.timers}/#{slot_id}/screens") |> json_response(200)

    assert screens |> Enum.map(& &1["id"]) |> Enum.sort() == Enum.sort([room, whole])

    path = "#{ctx.timers}/#{slot_id}/screens/#{room}/override"

    for view <- ["timer", "leaderboard", "wod"] do
      assert %{"screen" => %{"override" => %{"view" => ^view, "slot_id" => ^slot_id}} = screen} =
               ctx.coach |> send_json(:put, path, %{view: view}) |> json_response(200)

      assert screen["focus_changed"]["by"]["id"] == ctx.coach_user.id
    end

    assert %{"code" => "invalid_screen_override"} =
             ctx.coach |> send_json(:put, path, %{view: "bookings"}) |> json_response(422)

    assert %{"screen" => %{"override" => nil}} =
             ctx.coach |> recycle() |> delete(path) |> json_response(200)

    assert %{"screen" => %{"override" => %{"view" => "timer"}}} =
             ctx.coach
             |> send_json(:put, "#{ctx.timers}/#{slot_id}/screens/#{whole}/override", %{
               view: "timer"
             })
             |> json_response(200)
  end

  test "a coach of another class is refused", ctx do
    slot_id = class(ctx, ctx.coach_user.id, ctx.branch.id, DateTime.add(ctx.now, 600))
    room = screen(ctx, "Αίθουσα", ctx.branch.id)
    path = "#{ctx.timers}/#{slot_id}/screens/#{room}/override"

    assert %{"code" => "forbidden"} =
             ctx.other_coach
             |> get_json("#{ctx.timers}/#{slot_id}/screens")
             |> json_response(403)

    assert ctx.other_coach |> send_json(:put, path, %{view: "timer"}) |> json_response(403)

    ctx.coach |> send_json(:put, path, %{view: "timer"}) |> json_response(200)
    assert ctx.other_coach |> recycle() |> delete(path) |> json_response(403)

    for conn <- [ctx.member] do
      assert conn |> get_json("#{ctx.timers}/#{slot_id}/screens") |> json_response(403)
      assert conn |> send_json(:put, path, %{view: "timer"}) |> json_response(403)
    end
  end

  test "a coach cannot reach another branch's screen, another day's class or another choice",
       ctx do
    today = class(ctx, ctx.coach_user.id, ctx.branch.id, DateTime.add(ctx.now, 600))
    tomorrow = class(ctx, ctx.coach_user.id, ctx.branch.id, DateTime.add(ctx.now, 86_400))
    room = screen(ctx, "Αίθουσα", ctx.branch.id)
    elsewhere = screen(ctx, "Παγκράτι TV", ctx.other_branch.id)

    assert ctx.coach
           |> send_json(:put, "#{ctx.timers}/#{today}/screens/#{elsewhere}/override", %{
             view: "timer"
           })
           |> json_response(403)

    assert ctx.coach
           |> send_json(:put, "#{ctx.timers}/#{tomorrow}/screens/#{room}/override", %{
             view: "timer"
           })
           |> json_response(403)

    # Staff pinned the day's WOD for everyone: the coach may pin over it, not unpin it.
    ctx.owner
    |> send_json(:put, "#{ctx.admin}/#{room}/override", %{view: "wod"})
    |> json_response(200)

    path = "#{ctx.timers}/#{today}/screens/#{room}/override"
    assert ctx.coach |> recycle() |> delete(path) |> json_response(403)

    assert %{"code" => "box_screen_not_found"} =
             ctx.coach
             |> send_json(
               :put,
               "#{ctx.timers}/#{today}/screens/#{Ecto.UUID.generate()}/override",
               %{view: "timer"}
             )
             |> json_response(404)

    assert ctx.coach
           |> get_json("#{ctx.timers}/#{Ecto.UUID.generate()}/screens")
           |> json_response(404)
  end

  test "owners keep their rights from the remote, any view", ctx do
    slot_id = class(ctx, ctx.coach_user.id, ctx.branch.id, DateTime.add(ctx.now, 600))
    room = screen(ctx, "Αίθουσα", ctx.branch.id)

    assert %{"views" => ["wod", "timer", "leaderboard", "bookings", "class"]} =
             ctx.owner |> get_json("#{ctx.timers}/#{slot_id}/screens") |> json_response(200)

    path = "#{ctx.timers}/#{slot_id}/screens/#{room}/override"

    assert %{"screen" => %{"override" => %{"view" => "class"}}} =
             ctx.owner |> send_json(:put, path, %{view: "class"}) |> json_response(200)

    assert %{"screen" => %{"override" => nil}} =
             ctx.owner |> recycle() |> delete(path) |> json_response(200)
  end
end
