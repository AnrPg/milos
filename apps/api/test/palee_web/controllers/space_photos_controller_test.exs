defmodule PaleeWeb.SpacePhotosControllerTest do
  @moduledoc """
  ADR-290: what the floor plans of ADR-202 grow into. Room photos (each one
  off the public page until its uploader turns it on), the visual cleaning
  checklist a janitor answers point by point, photos and pins on the machine
  log, and the room of a class shown on the floor plan to the people who
  see the class when the gym turns that on.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures
  import Palee.TestSupport.ImageFixtures

  alias Palee.{Media, Notifications, Organizations, Repo}
  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
  alias Palee.TestSupport.MemoryObjectStore

  setup %{conn: conn} do
    MemoryObjectStore.start()

    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    person = fn role ->
      user = if role == :owner, do: admin_fixture(), else: user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      {user, put_bearer_token(conn, user)}
    end

    {owner_user, owner} = person.(:owner)
    {desk_user, desk} = person.(:front_desk)
    {_coach_user, coach} = person.(:coach)
    {_janitor_user, janitor} = person.(:janitor)
    {_member_user, member} = person.(:member)

    {:ok, context} =
      Organizations.resolve_tenant_context(owner_user, Organizations.legacy_organization_slug())

    slug = Organizations.legacy_organization_slug()

    %{
      organization: organization,
      context: context,
      owner_user: owner_user,
      owner: owner,
      desk_user: desk_user,
      desk: desk,
      coach: coach,
      janitor: janitor,
      member: member,
      anonymous: conn,
      staff: "/api/org/#{slug}/staff",
      org: "/api/org/#{slug}",
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

  # A ready upload of `purpose` through `path` (e.g. "space-photos").
  defp upload!(ctx, conn, path) do
    body = jpeg(800, 600)

    %{"media_id" => media_id} =
      conn
      |> send_json(:post, "#{ctx.staff}/#{path}/uploads", %{
        content_type: "image/jpeg",
        byte_size: byte_size(body)
      })
      |> json_response(200)

    media = Media.get(%{organization_id: ctx.organization.id}, :tenant, media_id)
    :ok = MemoryObjectStore.put_object(:media_private, media.object_key, body, "image/jpeg")

    %{"media" => %{"status" => "ready"}} =
      conn
      |> send_json(:post, "#{ctx.staff}/#{path}/uploads/#{media_id}/complete", %{})
      |> json_response(200)

    media_id
  end

  defp floor_plan!(ctx, name) do
    media_id = upload!(ctx, ctx.owner, "floor-plans")

    ctx.owner
    |> send_json(:post, "#{ctx.staff}/floor-plans", %{name: name, media_id: media_id})
    |> json_response(201)
    |> Map.fetch!("floor_plan")
  end

  @square [[0.1, 0.1], [0.5, 0.1], [0.5, 0.4], [0.1, 0.4]]

  test "room photos: front desk adds them; each starts off the public page; reorder and delete",
       ctx do
    space = create_space(ctx, %{name: "Studio"})
    path = "#{ctx.staff}/spaces/#{space["id"]}/photos"

    first = upload!(ctx, ctx.desk, "space-photos")

    assert %{"photo" => %{"id" => a, "public" => false, "url" => url, "caption" => "Mirrors"}} =
             ctx.desk
             |> send_json(:post, path, %{media_id: first, caption: " Mirrors "})
             |> json_response(201)

    assert url
    assert Media.get(%{organization_id: ctx.organization.id}, :tenant, first).attached_at

    # A floor-plan or cleaning upload is not a room photo.
    cleaning = upload!(ctx, ctx.desk, "cleaning-photos")
    assert ctx.desk |> send_json(:post, path, %{media_id: cleaning}) |> json_response(422)

    # Coaches and janitors neither upload nor add.
    assert ctx.coach
           |> send_json(:post, "#{ctx.staff}/space-photos/uploads", %{
             content_type: "image/jpeg",
             byte_size: 100
           })
           |> json_response(403)

    assert ctx.janitor
           |> send_json(:post, path, %{media_id: first})
           |> json_response(403)

    second = upload!(ctx, ctx.owner, "space-photos")

    assert %{"photo" => %{"id" => b}} =
             ctx.owner |> send_json(:post, path, %{media_id: second}) |> json_response(201)

    assert %{"photo" => %{"public" => true, "caption" => nil}} =
             ctx.desk
             |> send_json(:patch, "#{ctx.staff}/space-photos/#{b}", %{public: true, caption: ""})
             |> json_response(200)

    assert %{"photos" => [%{"id" => ^b}, %{"id" => ^a}]} =
             ctx.desk
             |> send_json(:put, "#{path}/order", %{ids: [b, a]})
             |> json_response(200)

    assert %{"space" => %{"photos" => [%{"id" => ^b}, %{"id" => ^a}], "points" => []}} =
             ctx.coach |> get_json("#{ctx.staff}/spaces/#{space["id"]}") |> json_response(200)

    assert ctx.desk
           |> send_json(:delete, "#{ctx.staff}/space-photos/#{a}", %{})
           |> response(204)

    refute Media.get(%{organization_id: ctx.organization.id}, :tenant, first)

    assert %{"space" => %{"photos" => [%{"id" => ^b}]}} =
             ctx.coach |> get_json("#{ctx.staff}/spaces/#{space["id"]}") |> json_response(200)
  end

  test "the gym shows floor plans in classes; a hidden floor keeps its plan back", ctx do
    assert %{"settings" => %{"floor_plans_in_classes" => false}} =
             ctx.owner |> get_json("#{ctx.staff}/space-settings") |> json_response(200)

    assert ctx.desk
           |> send_json(:put, "#{ctx.staff}/space-settings", %{floor_plans_in_classes: true})
           |> json_response(403)

    plan = floor_plan!(ctx, "Ground floor")
    assert plan["shown_in_classes"] == true

    space = create_space(ctx, %{name: "Main hall", directions: "Left of the desk"})

    ctx.owner
    |> send_json(:patch, "#{ctx.staff}/spaces/#{space["id"]}", %{
      floor_plan_id: plan["id"],
      area: %{points: @square}
    })
    |> json_response(200)

    workout = workout_fixture(ctx.owner_user)
    slot = slot_fixture(workout, %{space_id: space["id"]})
    room = "#{ctx.org}/schedule/slots/#{slot.id}/space"

    # Off: members see the room's name only; staff who see spaces see everything.
    assert ctx.member |> get_json(room) |> json_response(403)

    assert %{"floor_plan" => %{"id" => plan_id}, "area" => %{"points" => _}, "photos" => []} =
             ctx.coach |> get_json(room) |> json_response(200)

    assert plan_id == plan["id"]

    assert %{"settings" => %{"floor_plans_in_classes" => true}} =
             ctx.owner
             |> send_json(:put, "#{ctx.staff}/space-settings", %{floor_plans_in_classes: true})
             |> json_response(200)

    assert %{
             "space" => %{"name" => "Main hall", "directions" => "Left of the desk"},
             "floor_plan" => %{"image_url" => _},
             "area" => %{"points" => _}
           } = ctx.member |> get_json(room) |> json_response(200)

    # The floor hidden: the room without its plan.
    assert %{"floor_plan" => %{"shown_in_classes" => false}} =
             ctx.owner
             |> send_json(:patch, "#{ctx.staff}/floor-plans/#{plan["id"]}", %{
               shown_in_classes: false
             })
             |> json_response(200)

    assert %{"floor_plan" => nil, "area" => nil, "space" => %{"name" => "Main hall"}} =
             ctx.member |> get_json(room) |> json_response(200)

    assert %{"floor_plan" => %{"id" => _}} = ctx.coach |> get_json(room) |> json_response(200)
  end

  test "cleaning points: the janitor answers each one; a point not cleaned needs a note and tells front desk",
       ctx do
    space = create_space(ctx, %{name: "Showers"})
    points = "#{ctx.staff}/spaces/#{space["id"]}/cleaning-points"

    assert %{"point" => %{"id" => drains}} =
             ctx.desk
             |> send_json(:post, points, %{
               media_id: upload!(ctx, ctx.desk, "cleaning-photos"),
               instruction: "Drains and grates"
             })
             |> json_response(201)

    assert %{"point" => %{"id" => mirrors}} =
             ctx.owner
             |> send_json(:post, points, %{
               media_id: upload!(ctx, ctx.owner, "cleaning-photos"),
               instruction: "Mirrors"
             })
             |> json_response(201)

    assert %{"code" => _} =
             ctx.desk
             |> send_json(:post, points, %{
               media_id: upload!(ctx, ctx.desk, "cleaning-photos"),
               instruction: " "
             })
             |> json_response(422)

    cleaning = "#{ctx.staff}/cleaning"

    assert %{"areas" => [%{"points" => [%{"id" => ^drains, "url" => _}, %{"id" => ^mirrors}]}]} =
             ctx.janitor |> get_json("#{cleaning}/areas") |> json_response(200)

    %{"entry" => %{"id" => entry_id}} =
      ctx.janitor
      |> send_json(:post, "#{cleaning}/entries", %{area_id: space["id"]})
      |> json_response(201)

    finish = "#{cleaning}/entries/#{entry_id}/finish"

    assert %{"code" => "cleaning_point_unanswered"} =
             ctx.janitor
             |> send_json(:post, finish, %{
               point_results: [%{point_id: drains, status: "cleaned"}]
             })
             |> json_response(422)

    assert %{"code" => "cleaning_point_note_required"} =
             ctx.janitor
             |> send_json(:post, finish, %{
               point_results: [
                 %{point_id: drains, status: "cleaned"},
                 %{point_id: mirrors, status: "not_cleaned", note: " "}
               ]
             })
             |> json_response(422)

    after_photo = upload!(ctx, ctx.janitor, "cleaning-photos")

    assert %{"entry" => %{"point_results" => [cleaned, missed]}} =
             ctx.janitor
             |> send_json(:post, finish, %{
               point_results: [
                 %{point_id: mirrors, status: "not_cleaned", note: "Out of spray"},
                 %{point_id: drains, status: "cleaned", after_media_id: after_photo}
               ]
             })
             |> json_response(200)

    assert %{
             "point_id" => ^drains,
             "status" => "cleaned",
             "instruction" => "Drains and grates",
             "after_url" => after_url
           } = cleaned

    assert after_url
    assert %{"point_id" => ^mirrors, "status" => "not_cleaned", "note" => "Out of spray"} = missed

    assert Enum.any?(
             Notifications.list_for_user(ctx.desk_user.id),
             &(&1.type == "cleaning_point_not_cleaned")
           )

    # The log keeps the answers, as the points read then.
    ctx.desk
    |> send_json(:patch, "#{ctx.staff}/cleaning-points/#{mirrors}", %{instruction: "Glass"})
    |> json_response(200)

    assert %{"entries" => [%{"point_results" => [_, %{"instruction" => "Mirrors"}]}]} =
             ctx.desk |> get_json("#{cleaning}/entries") |> json_response(200)
  end

  test "machine log photos (at most 10) and pins on the floor plan", ctx do
    plan = floor_plan!(ctx, "Ground floor")
    cardio = create_space(ctx, %{name: "Cardio"})
    bare = create_space(ctx, %{name: "Yard"})

    ctx.owner
    |> send_json(:patch, "#{ctx.staff}/spaces/#{cardio["id"]}", %{
      floor_plan_id: plan["id"],
      area: %{points: @square}
    })
    |> json_response(200)

    %{"machine" => %{"id" => machine_id}} =
      ctx.owner
      |> send_json(:post, "#{ctx.staff}/inventory/machines", %{name: "Treadmill", quantity: 2})
      |> json_response(201)

    placements = "#{ctx.staff}/inventory/machines/#{machine_id}/placements"

    assert %{"code" => "invalid_machine_position"} =
             ctx.owner
             |> send_json(:put, placements, %{
               placements: [
                 %{space_id: cardio["id"], quantity: 1, positions: [[0.2, 0.2], [0.3, 0.3]]}
               ]
             })
             |> json_response(422)

    assert %{"code" => "space_not_on_plan"} =
             ctx.owner
             |> send_json(:put, placements, %{
               placements: [%{space_id: bare["id"], quantity: 1, positions: [[0.5, 0.5]]}]
             })
             |> json_response(422)

    assert %{"placements" => [%{"positions" => [[0.2, 0.25]]}]} =
             ctx.owner
             |> send_json(:put, placements, %{
               placements: [%{space_id: cardio["id"], quantity: 2, positions: [[0.2, 0.25]]}]
             })
             |> json_response(200)

    events = "#{ctx.staff}/inventory/machines/#{machine_id}/events"
    photo = upload!(ctx, ctx.desk, "inventory/machine-photos")

    assert %{"event" => %{"photos" => [%{"id" => ^photo, "url" => _}]}} =
             ctx.desk
             |> send_json(:post, events, %{kind: "issue", body: "Belt slips", media_ids: [photo]})
             |> json_response(201)

    assert ctx.desk
           |> send_json(:post, events, %{
             kind: "note",
             media_ids: Enum.map(1..11, fn _ -> Ecto.UUID.generate() end)
           })
           |> json_response(422)

    assert %{
             "events" => [%{"photos" => [_]}],
             "places" => [
               %{
                 "space_name" => "Cardio",
                 "positions" => [[0.2, 0.25]],
                 "floor_plan" => %{"id" => _},
                 "area" => %{"points" => _}
               }
             ]
           } = ctx.coach |> get_json(events) |> json_response(200)
  end

  test "the public box page shows only the room photos their uploader made public", ctx do
    space = create_space(ctx, %{name: "Studio", description: "Bright, wooden floor"})
    path = "#{ctx.staff}/spaces/#{space["id"]}/photos"

    %{"photo" => %{"id" => shown}} =
      ctx.desk
      |> send_json(:post, path, %{
        media_id: upload!(ctx, ctx.desk, "space-photos"),
        caption: "Morning light"
      })
      |> json_response(201)

    ctx.desk
    |> send_json(:post, path, %{media_id: upload!(ctx, ctx.desk, "space-photos")})
    |> json_response(201)

    ctx.desk
    |> send_json(:patch, "#{ctx.staff}/space-photos/#{shown}", %{public: true})
    |> json_response(200)

    {:ok, profile} =
      UpdateBoxPublicProfile.call(ctx.context, %{
        "about" => "Ένα box στην Κυψέλη.",
        "disciplines" => ["crossfit"]
      })

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(ctx.context, %{"lock_version" => profile.lock_version})

    assert %{"rooms" => [room]} =
             ctx.anonymous
             |> get_json("/api/public/boxes/#{ctx.slug}")
             |> json_response(200)

    assert %{
             "name" => "Studio",
             "description" => "Bright, wooden floor",
             "photos" => [%{"id" => ^shown, "caption" => "Morning light", "url" => _}]
           } = room
  end
end
