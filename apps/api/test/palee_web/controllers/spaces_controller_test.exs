defmodule PaleeWeb.SpacesControllerTest do
  @moduledoc """
  ADR-202: Settings › Spaces. Owners and admins manage spaces and floor
  plans; front desk edits details and unavailability; coaches read them.
  A class is refused while its space is unavailable; two classes in one
  space at the same time are a warning on the schedule. Machines record how
  many stand in which space.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures
  import Palee.TestSupport.ImageFixtures

  alias Palee.{Facility, Media, Organizations, Repo}
  alias Palee.TestSupport.MemoryObjectStore

  setup %{conn: conn} do
    MemoryObjectStore.start()

    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    staff = fn role ->
      user = if role == :owner, do: admin_fixture(), else: user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      {user, put_bearer_token(conn, user)}
    end

    {owner_user, owner} = staff.(:owner)
    {desk_user, desk} = staff.(:front_desk)
    {_coach_user, coach} = staff.(:coach)
    {_janitor_user, janitor} = staff.(:janitor)

    {:ok, context} =
      Organizations.resolve_tenant_context(owner_user, Organizations.legacy_organization_slug())

    slug = Organizations.legacy_organization_slug()

    %{
      organization: organization,
      context: context,
      owner: owner,
      desk: desk,
      desk_user: desk_user,
      coach: coach,
      janitor: janitor,
      staff: "/api/org/#{slug}/staff",
      admin: "/api/org/#{slug}/admin",
      slug: slug
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp get_json(conn, path), do: conn |> recycle() |> get(path)

  defp create_space(ctx, body) do
    ctx.owner
    |> send_json(:post, "#{ctx.staff}/spaces", body)
    |> json_response(201)
    |> Map.fetch!("space")
  end

  defp future(hours) do
    DateTime.utc_now()
    |> DateTime.add(2 * 86_400 + hours * 3_600, :second)
    |> DateTime.truncate(:second)
    |> Map.put(:minute, 0)
    |> Map.put(:second, 0)
  end

  defp class_body(class_type, space_id, at, extra \\ %{}) do
    Map.merge(
      %{
        class_type_id: class_type.id,
        name: "WOD",
        duration_minutes: 60,
        scheduled_at: DateTime.to_iso8601(at),
        capacity: 10,
        auto_approve: true,
        booking_timeout_minutes: 30,
        space_id: space_id
      },
      extra
    )
  end

  test "owners add, edit and archive spaces; front desk edits details only; coaches read", ctx do
    space =
      create_space(ctx, %{
        name: " Cardio room ",
        description: "Treadmills and bikes",
        directions: "First floor, left",
        tasks: ["Mop", "Wipe screens"]
      })

    assert %{
             "name" => "Cardio room",
             "directions" => "First floor, left",
             "tasks" => ["Mop", "Wipe screens"],
             "location_id" => nil,
             "unavailability" => []
           } = space

    # Front desk: details, but not tasks, branch or floor plan, and no adding or archiving.
    assert %{"space" => %{"directions" => "Ground floor"}} =
             ctx.desk
             |> send_json(:patch, "#{ctx.staff}/spaces/#{space["id"]}", %{
               directions: "Ground floor"
             })
             |> json_response(200)

    assert ctx.desk
           |> send_json(:patch, "#{ctx.staff}/spaces/#{space["id"]}", %{tasks: []})
           |> json_response(403)

    assert ctx.desk |> send_json(:post, "#{ctx.staff}/spaces", %{name: "X"}) |> json_response(403)

    assert ctx.desk
           |> send_json(:post, "#{ctx.staff}/spaces/#{space["id"]}/archive", %{})
           |> json_response(403)

    # Coaches read; janitors see spaces only through the cleaning list.
    assert %{"spaces" => [%{"name" => "Cardio room"}], "floor_plans" => []} =
             ctx.coach |> get_json("#{ctx.staff}/spaces") |> json_response(200)

    assert ctx.coach
           |> send_json(:patch, "#{ctx.staff}/spaces/#{space["id"]}", %{name: "Nope"})
           |> json_response(403)

    assert ctx.janitor |> get_json("#{ctx.staff}/spaces") |> json_response(403)

    assert %{"space" => %{"archived_at" => archived}} =
             ctx.owner
             |> send_json(:post, "#{ctx.staff}/spaces/#{space["id"]}/archive", %{})
             |> json_response(200)

    assert archived
    assert %{"spaces" => []} = ctx.owner |> get_json("#{ctx.staff}/spaces") |> json_response(200)

    assert %{"spaces" => [_]} =
             ctx.owner
             |> get_json("#{ctx.staff}/spaces?include_archived=true")
             |> json_response(200)

    assert %{"space" => %{"archived_at" => nil}} =
             ctx.owner
             |> send_json(:post, "#{ctx.staff}/spaces/#{space["id"]}/restore", %{})
             |> json_response(200)
  end

  test "a gym may let its front desk manage spaces in Roles", ctx do
    assert ctx.owner
           |> send_json(:put, "#{ctx.admin}/role-access/front_desk", %{
             capabilities: ["manage_spaces"]
           })
           |> json_response(200)

    assert ctx.desk
           |> send_json(:post, "#{ctx.staff}/spaces", %{name: "Rehab"})
           |> json_response(201)
  end

  test "spaces belong to a branch; branch staff see their own branches only", ctx do
    {:ok, kifisia} = Facility.create_location(ctx.context, %{name: "Kifisia"})
    {:ok, marousi} = Facility.create_location(ctx.context, %{name: "Marousi"})

    create_space(ctx, %{name: "Kifisia hall", location_id: kifisia.id})
    marousi_space = create_space(ctx, %{name: "Marousi hall", location_id: marousi.id})

    assert ctx.owner
           |> send_json(:put, "#{ctx.admin}/users/#{ctx.desk_user.id}/location-scope", %{
             all_locations: false,
             location_ids: [kifisia.id]
           })
           |> json_response(200)

    assert %{"spaces" => [%{"name" => "Kifisia hall"}]} =
             ctx.desk |> get_json("#{ctx.staff}/spaces") |> json_response(200)

    assert ctx.desk
           |> send_json(:patch, "#{ctx.staff}/spaces/#{marousi_space["id"]}", %{name: "Mine"})
           |> json_response(403)

    assert %{"spaces" => [%{"name" => "Marousi hall"}]} =
             ctx.owner
             |> get_json("#{ctx.staff}/spaces?location_id=#{marousi.id}")
             |> json_response(200)
  end

  test "floor plans: upload, draw a space's area, delete clears the drawing", ctx do
    body = jpeg(1_200, 800)

    assert ctx.desk
           |> send_json(:post, "#{ctx.staff}/floor-plans/uploads", %{
             content_type: "image/jpeg",
             byte_size: byte_size(body)
           })
           |> json_response(403)

    assert %{"media_id" => media_id} =
             ctx.owner
             |> send_json(:post, "#{ctx.staff}/floor-plans/uploads", %{
               content_type: "image/jpeg",
               byte_size: byte_size(body)
             })
             |> json_response(200)

    media = Media.get(%{organization_id: ctx.organization.id}, :tenant, media_id)
    :ok = MemoryObjectStore.put_object(:media_private, media.object_key, body, "image/jpeg")

    assert %{"media" => %{"status" => "ready"}} =
             ctx.owner
             |> send_json(:post, "#{ctx.staff}/floor-plans/uploads/#{media_id}/complete", %{})
             |> json_response(200)

    assert %{"floor_plan" => %{"id" => plan_id, "image_url" => url, "width" => 1_200}} =
             ctx.owner
             |> send_json(:post, "#{ctx.staff}/floor-plans", %{
               name: "Ground floor",
               media_id: media_id
             })
             |> json_response(201)

    assert url
    assert Media.get(%{organization_id: ctx.organization.id}, :tenant, media_id).attached_at

    space = create_space(ctx, %{name: "Cardio"})

    assert %{"space" => %{"floor_plan_id" => ^plan_id, "area" => %{"points" => points}}} =
             ctx.owner
             |> send_json(:patch, "#{ctx.staff}/spaces/#{space["id"]}", %{
               floor_plan_id: plan_id,
               area: %{points: [[0.1, 0.1], [0.5, 0.1], [0.5, 0.4], [0.1, 0.4]]}
             })
             |> json_response(200)

    assert length(points) == 4

    assert ctx.owner
           |> send_json(:patch, "#{ctx.staff}/spaces/#{space["id"]}", %{
             area: %{points: [[0.1, 0.1], [0.5, 0.1]]}
           })
           |> json_response(422)

    # Front desk cannot draw.
    assert ctx.desk
           |> send_json(:patch, "#{ctx.staff}/spaces/#{space["id"]}", %{area: nil})
           |> json_response(403)

    assert %{"floor_plans" => [%{"id" => ^plan_id, "name" => "Ground floor"}]} =
             ctx.coach |> get_json("#{ctx.staff}/spaces") |> json_response(200)

    assert ctx.owner
           |> send_json(:delete, "#{ctx.staff}/floor-plans/#{plan_id}", %{})
           |> json_response(200)

    assert %{"space" => %{"floor_plan_id" => nil, "area" => nil}} =
             ctx.owner |> get_json("#{ctx.staff}/spaces/#{space["id"]}") |> json_response(200)
  end

  test "a class in an unavailable space is refused; overlapping classes are only flagged", ctx do
    class_type = class_type_fixture(%{name: "CrossFit"})
    space = create_space(ctx, %{name: "Main hall"})
    other = create_space(ctx, %{name: "Studio"})
    slots = "#{ctx.admin}/schedule/slots"

    starts = future(0)

    assert %{"unavailability" => window, "affected_classes" => []} =
             ctx.desk
             |> send_json(:post, "#{ctx.staff}/spaces/#{space["id"]}/unavailability", %{
               starts_at: DateTime.to_iso8601(starts),
               ends_at: DateTime.to_iso8601(DateTime.add(starts, 3 * 3_600, :second)),
               reason: "Floor repair"
             })
             |> json_response(201)

    assert ctx.coach
           |> send_json(:post, "#{ctx.staff}/spaces/#{space["id"]}/unavailability", %{
             starts_at: DateTime.to_iso8601(starts),
             ends_at: DateTime.to_iso8601(DateTime.add(starts, 3_600, :second))
           })
           |> json_response(403)

    assert %{"code" => "invalid_unavailability"} =
             ctx.owner
             |> send_json(:post, "#{ctx.staff}/spaces/#{space["id"]}/unavailability", %{
               starts_at: DateTime.to_iso8601(starts),
               ends_at: DateTime.to_iso8601(starts)
             })
             |> json_response(422)

    assert %{"code" => "space_unavailable", "reason" => "Floor repair"} =
             ctx.owner
             |> send_json(:post, slots, class_body(class_type, space["id"], future(1)))
             |> json_response(409)

    # Before the repair it is fine; twice at once in the same space too, with a warning.
    early = DateTime.add(starts, -2 * 3_600, :second)

    assert %{"slot" => %{"id" => first_id, "space_id" => space_id}} =
             ctx.owner
             |> send_json(:post, slots, class_body(class_type, space["id"], early))
             |> json_response(201)

    assert space_id == space["id"]

    assert %{"slot" => %{"id" => second_id}} =
             ctx.owner
             |> send_json(
               :post,
               slots,
               class_body(class_type, space["id"], DateTime.add(early, 1_800, :second))
             )
             |> json_response(201)

    assert %{"slot" => %{"id" => third_id}} =
             ctx.owner
             |> send_json(:post, slots, class_body(class_type, other["id"], early))
             |> json_response(201)

    # Moving a class into the repair is refused.
    assert %{"code" => "space_unavailable"} =
             ctx.owner
             |> send_json(
               :patch,
               "#{slots}/#{first_id}",
               class_body(class_type, space["id"], future(1))
             )
             |> json_response(409)

    # An archived space takes no new classes.
    ctx.owner |> send_json(:post, "#{ctx.staff}/spaces/#{other["id"]}/archive", %{})

    assert %{"code" => "space_archived"} =
             ctx.owner
             |> send_json(:post, slots, class_body(class_type, other["id"], future(30)))
             |> json_response(422)

    from = DateTime.add(early, -3_600, :second)

    schedule =
      ctx.owner
      |> get_json(
        "/api/org/#{ctx.slug}/schedule?start_at=#{URI.encode_www_form(DateTime.to_iso8601(from))}&end_at=#{URI.encode_www_form(DateTime.to_iso8601(DateTime.add(from, 86_400, :second)))}&days=7"
      )
      |> json_response(200)

    by_id = Map.new(schedule["slots"], &{&1["id"], &1})

    assert %{"space" => %{"name" => "Main hall"}, "space_overlap" => true} = by_id[first_id]
    assert %{"space_overlap" => true} = by_id[second_id]

    assert %{"space" => %{"name" => "Studio"}, "space_overlap" => false} = by_id[third_id]

    # The space's detail lists its upcoming classes.
    assert %{"space" => %{"classes" => classes, "unavailability" => [%{"id" => window_id}]}} =
             ctx.coach |> get_json("#{ctx.staff}/spaces/#{space["id"]}") |> json_response(200)

    assert Enum.map(classes, & &1["id"]) == [first_id, second_id]
    assert window_id == window["id"]

    # Lifting the repair lets the class move in; a new window reports it.
    assert ctx.desk
           |> send_json(
             :delete,
             "#{ctx.staff}/spaces/#{space["id"]}/unavailability/#{window_id}",
             %{}
           )
           |> json_response(200)

    assert %{"slot" => _} =
             ctx.owner
             |> send_json(
               :patch,
               "#{slots}/#{first_id}",
               class_body(class_type, space["id"], future(1))
             )
             |> json_response(200)

    assert %{"affected_classes" => [%{"id" => ^first_id}]} =
             ctx.owner
             |> send_json(:post, "#{ctx.staff}/spaces/#{space["id"]}/unavailability", %{
               starts_at: DateTime.to_iso8601(starts),
               ends_at: DateTime.to_iso8601(DateTime.add(starts, 3 * 3_600, :second))
             })
             |> json_response(201)
  end

  test "a series takes a space and is refused when one of its classes falls in a window",
       ctx do
    class_type = class_type_fixture(%{name: "Yoga"})
    space = create_space(ctx, %{name: "Studio"})
    starts_on = Date.add(Date.utc_today(), 2)

    series = %{
      class_type_id: class_type.id,
      name: "Morning yoga",
      duration_minutes: 60,
      timezone: "Etc/UTC",
      starts_on: starts_on,
      ends_on: Date.add(starts_on, 6),
      local_start_time: "07:00:00",
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      capacity: 10,
      auto_approve: true,
      booking_timeout_minutes: 30,
      space_id: space["id"]
    }

    repair = DateTime.new!(Date.add(starts_on, 3), ~T[06:30:00], "Etc/UTC")

    assert %{"unavailability" => %{"id" => window_id}} =
             ctx.owner
             |> send_json(:post, "#{ctx.staff}/spaces/#{space["id"]}/unavailability", %{
               starts_at: DateTime.to_iso8601(repair),
               ends_at: DateTime.to_iso8601(DateTime.add(repair, 3_600, :second)),
               reason: "Painting"
             })
             |> json_response(201)

    assert %{"code" => "space_unavailable", "class_starts_at" => _} =
             ctx.owner
             |> send_json(:post, "#{ctx.admin}/schedule/slots/series", series)
             |> json_response(409)

    ctx.owner
    |> send_json(:delete, "#{ctx.staff}/spaces/#{space["id"]}/unavailability/#{window_id}", %{})
    |> json_response(200)

    assert %{"series" => %{"space_id" => space_id}} =
             ctx.owner
             |> send_json(:post, "#{ctx.admin}/schedule/slots/series", series)
             |> json_response(201)

    assert space_id == space["id"]

    assert %{"space" => %{"classes" => classes}} =
             ctx.owner |> get_json("#{ctx.staff}/spaces/#{space["id"]}") |> json_response(200)

    assert length(classes) == 7
  end

  test "machines record how many stand in which space; never more than owned", ctx do
    cardio = create_space(ctx, %{name: "Cardio"})
    rehab = create_space(ctx, %{name: "Rehab"})

    assert %{"machine" => %{"id" => machine_id, "placements" => [], "unassigned" => 6}} =
             ctx.owner
             |> send_json(:post, "#{ctx.staff}/inventory/machines", %{
               name: "Treadmill",
               quantity: 6
             })
             |> json_response(201)

    path = "#{ctx.staff}/inventory/machines/#{machine_id}/placements"

    assert %{"placements" => placements, "unassigned" => 0} =
             ctx.desk
             |> send_json(:put, path, %{
               placements: [
                 %{space_id: cardio["id"], quantity: 5},
                 %{space_id: rehab["id"], quantity: 1}
               ]
             })
             |> json_response(200)

    assert length(placements) == 2

    assert %{"code" => "placement_exceeds_quantity"} =
             ctx.owner
             |> send_json(:put, path, %{placements: [%{space_id: cardio["id"], quantity: 7}]})
             |> json_response(422)

    # Owning fewer than are placed is refused too.
    assert %{"code" => "placement_exceeds_quantity"} =
             ctx.owner
             |> send_json(:patch, "#{ctx.staff}/inventory/machines/#{machine_id}", %{quantity: 4})
             |> json_response(422)

    assert ctx.coach
           |> send_json(:put, path, %{placements: []})
           |> json_response(403)

    assert %{"machines" => [%{"placements" => [_, _], "unassigned" => 0}]} =
             ctx.coach |> get_json("#{ctx.staff}/inventory/machines") |> json_response(200)

    assert %{"space" => %{"equipment" => [%{"name" => "Treadmill", "quantity" => 5}]}} =
             ctx.coach |> get_json("#{ctx.staff}/spaces/#{cardio["id"]}") |> json_response(200)

    assert %{"placements" => [%{"quantity" => 4}], "unassigned" => 2} =
             ctx.owner
             |> send_json(:put, path, %{placements: [%{space_id: cardio["id"], quantity: 4}]})
             |> json_response(200)

    assert %{"space" => %{"equipment" => []}} =
             ctx.owner |> get_json("#{ctx.staff}/spaces/#{rehab["id"]}") |> json_response(200)
  end
end
