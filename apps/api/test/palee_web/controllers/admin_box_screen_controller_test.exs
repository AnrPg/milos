defmodule PaleeWeb.AdminBoxScreenControllerTest do
  @moduledoc """
  ADR-253 over HTTP, staff side: owners add screens and get a pairing code,
  rename, move and remove them, issue new codes and pin what a screen shows
  («Επιστροφή στο αυτόματο» returns it). Coaches and members cannot.
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
    {_coach_user, coach} = staff.(:coach)
    {_member_user, member} = staff.(:member)

    {:ok, context} =
      Organizations.resolve_tenant_context(owner_user, Organizations.legacy_organization_slug())

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    FixedBoxScreenClock.put(now)
    BoxScreenFixtures.set_gym_zone!(organization.id, BoxScreenFixtures.midday_zone(now))

    %{
      organization: organization,
      context: context,
      owner_user: owner_user,
      owner: owner,
      coach: coach,
      member: member,
      now: now,
      admin: "/api/org/#{Organizations.legacy_organization_slug()}/admin/box-screens"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp get_json(conn, path), do: conn |> recycle() |> get(path)

  test "owners add, list, rename and remove screens", ctx do
    assert %{"screens" => [], "max_screens" => 20, "override_views" => views} =
             ctx.owner |> get_json(ctx.admin) |> json_response(200)

    assert views == ["wod", "timer", "leaderboard", "bookings", "class"]

    assert %{
             "screen" => %{"id" => id, "name" => "Αίθουσα", "paired" => false} = screen,
             "pairing_code" => %{"code" => code, "expires_at" => expires_at}
           } =
             ctx.owner
             |> send_json(:post, ctx.admin, %{name: "Αίθουσα"})
             |> json_response(201)

    assert code =~ ~r/^[A-Z0-9]{4}-[A-Z0-9]{4}$/
    assert screen["pairing_expires_at"] == expires_at
    assert screen["location_id"] == nil
    assert screen["override"] == nil

    assert %{"screens" => [%{"id" => ^id}]} =
             ctx.owner |> get_json(ctx.admin) |> json_response(200)

    {:ok, branch} = Facility.create_location(ctx.context, %{name: "Κυψέλη"})

    assert %{"screen" => %{"name" => "Είσοδος", "location_id" => location_id}} =
             ctx.owner
             |> send_json(:patch, "#{ctx.admin}/#{id}", %{name: "Είσοδος", location_id: branch.id})
             |> json_response(200)

    assert location_id == branch.id

    assert %{"code" => "invalid_screen_name"} =
             ctx.owner
             |> send_json(:patch, "#{ctx.admin}/#{id}", %{name: "   "})
             |> json_response(422)

    assert %{"code" => "invalid_screen_branch"} =
             ctx.owner
             |> send_json(:patch, "#{ctx.admin}/#{id}", %{location_id: Ecto.UUID.generate()})
             |> json_response(422)

    assert %{"code" => "invalid_screen_branch"} =
             ctx.owner
             |> send_json(:post, ctx.admin, %{name: "TV", location_id: Ecto.UUID.generate()})
             |> json_response(422)

    assert %{"pairing_code" => %{"code" => second}} =
             ctx.owner
             |> send_json(:post, "#{ctx.admin}/#{id}/pairing-code", %{})
             |> json_response(201)

    refute second == code

    assert "" == ctx.owner |> recycle() |> delete("#{ctx.admin}/#{id}") |> response(204)

    assert %{"code" => "box_screen_not_found"} =
             ctx.owner |> recycle() |> delete("#{ctx.admin}/#{id}") |> json_response(404)

    assert %{"code" => "box_screen_not_found"} =
             ctx.owner
             |> send_json(:post, "#{ctx.admin}/#{Ecto.UUID.generate()}/pairing-code", %{})
             |> json_response(404)
  end

  test "a box has at most 20 screens", ctx do
    for n <- 1..20 do
      ctx.owner |> send_json(:post, ctx.admin, %{name: "TV #{n}"}) |> json_response(201)
    end

    assert %{"code" => "too_many_screens"} =
             ctx.owner |> send_json(:post, ctx.admin, %{name: "TV 21"}) |> json_response(409)
  end

  test "coaches and members cannot manage screens", ctx do
    for conn <- [ctx.coach, ctx.member] do
      assert conn |> get_json(ctx.admin) |> json_response(403)
      assert conn |> send_json(:post, ctx.admin, %{name: "TV"}) |> json_response(403)
    end
  end

  test "staff pin what a screen shows and return it to automatic", ctx do
    workout = workout_fixture(ctx.owner_user)
    slot = slot_fixture(workout)

    Repo.query!("UPDATE scheduled_classes SET scheduled_at = $1 WHERE id = $2", [
      DateTime.add(ctx.now, 60),
      Ecto.UUID.dump!(slot.id)
    ])

    %{"screen" => %{"id" => id}} =
      ctx.owner |> send_json(:post, ctx.admin, %{name: "TV"}) |> json_response(201)

    path = "#{ctx.admin}/#{id}/override"
    until = ctx.now |> DateTime.add(1800) |> DateTime.to_iso8601()

    assert %{"screen" => %{"override" => override, "focus_changed" => changed}} =
             ctx.owner
             |> send_json(:put, path, %{view: "class", slot_id: slot.id, until: until})
             |> json_response(200)

    assert %{"view" => "class", "slot_id" => slot_id, "until" => _until} = override
    assert slot_id == slot.id
    assert %{"by" => %{"id" => by}} = changed
    assert by == ctx.owner_user.id

    assert %{
             "screen" => %{
               "override" => %{"view" => "bookings", "slot_id" => nil, "until" => nil}
             }
           } =
             ctx.owner |> send_json(:put, path, %{view: "bookings"}) |> json_response(200)

    for bad <- [
          %{view: "class"},
          %{view: "wod", slot_id: Ecto.UUID.generate()},
          %{view: "wod", until: ctx.now |> DateTime.add(-60) |> DateTime.to_iso8601()}
        ] do
      assert %{"code" => "invalid_screen_override"} =
               ctx.owner |> send_json(:put, path, bad) |> json_response(422)
    end

    assert ctx.owner |> send_json(:put, path, %{view: "tv"}) |> json_response(422)

    assert %{"screen" => %{"override" => nil, "focus_changed" => %{"by" => %{"id" => ^by}}}} =
             ctx.owner |> recycle() |> delete(path) |> json_response(200)

    assert %{"code" => "box_screen_not_found"} =
             ctx.owner
             |> send_json(:put, "#{ctx.admin}/#{Ecto.UUID.generate()}/override", %{view: "wod"})
             |> json_response(404)

    assert ctx.coach |> send_json(:put, path, %{view: "wod"}) |> json_response(403)
  end
end
