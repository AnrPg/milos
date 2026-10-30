defmodule PaleeWeb.BoxScreenControllerTest do
  @moduledoc """
  ADR-253 over HTTP, the TV's side: pairing with a code (once), the display
  token (renewal, revocation, another device), and today's screen: the
  box's own day, its branch's classes and whole-box classes, WODs with
  their body, leaderboards of opted-in people only, bookings that name only
  first names, and the focus (automatic or pinned by staff).
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Community, Facility, Organizations, Repo, Scheduling}
  alias Palee.TestSupport.{BoxScreenFixtures, FixedBoxScreenClock}

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner_user = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner_user, :owner)
    slug = Organizations.legacy_organization_slug()
    {:ok, context} = Organizations.resolve_tenant_context(owner_user, slug)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    zone = BoxScreenFixtures.midday_zone(now)
    BoxScreenFixtures.set_gym_zone!(organization.id, zone)
    FixedBoxScreenClock.put(now)

    %{
      organization: organization,
      context: context,
      owner_user: owner_user,
      owner: put_bearer_token(conn, owner_user),
      tv: Phoenix.ConnTest.build_conn(),
      now: now,
      zone: zone,
      slug: slug,
      admin: "/api/org/#{slug}/admin/box-screens"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp with_token(conn, token),
    do: conn |> recycle() |> put_req_header("authorization", "Bearer " <> token)

  defp new_screen(ctx, body \\ %{name: "Αίθουσα"}) do
    %{"screen" => %{"id" => id}, "pairing_code" => %{"code" => code}} =
      ctx.owner |> send_json(:post, ctx.admin, body) |> json_response(201)

    {id, code}
  end

  defp pair(ctx, code), do: ctx.tv |> send_json(:post, "/api/box-screen/pair", %{code: code})

  defp member(name) do
    user = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, :member)

    Repo.query!("UPDATE users SET display_nickname = $1 WHERE id = $2", [
      name,
      Ecto.UUID.dump!(user.id)
    ])

    user
  end

  defp move_class(slot, at, location_id) do
    Repo.query!(
      "UPDATE scheduled_classes SET scheduled_at = $1, location_id = $2 WHERE id = $3",
      [at, location_id && Ecto.UUID.dump!(location_id), Ecto.UUID.dump!(slot.id)]
    )
  end

  test "a code pairs one TV once; the token opens only this screen's endpoints", ctx do
    {id, code} = new_screen(ctx)
    box_id = ctx.organization.id

    # The box id is the TV's realtime topic (`box_screen:<id>`).
    assert %{
             "token" => token,
             "expires_at" => expires_at,
             "screen" => %{"id" => ^id, "name" => "Αίθουσα"},
             "box" => %{"id" => ^box_id, "name" => _name}
           } = ctx |> pair(String.downcase(code)) |> json_response(201)

    {:ok, expires_at, 0} = DateTime.from_iso8601(expires_at)
    assert DateTime.diff(expires_at, ctx.now, :day) == 90

    assert %{"code" => "invalid_pairing_code"} = ctx |> pair(code) |> json_response(422)
    assert %{"code" => "invalid_pairing_code"} = ctx |> pair("AAAA-AAAA") |> json_response(422)

    assert %{"screen" => %{"id" => ^id}, "box" => %{"id" => ^box_id}} =
             ctx.tv |> with_token(token) |> get("/api/box-screen/today") |> json_response(200)

    assert %{"code" => "invalid_screen_token"} =
             ctx.tv |> recycle() |> get("/api/box-screen/today") |> json_response(401)

    assert %{"code" => "invalid_screen_token"} =
             ctx.tv |> with_token("nope") |> get("/api/box-screen/today") |> json_response(401)

    # The display token is not a session: staff and member routes refuse it.
    assert ctx.tv |> with_token(token) |> get(ctx.admin) |> json_response(401)
    assert ctx.tv |> with_token(token) |> get("/api/me/clubs") |> json_response(401)

    assert %{"screens" => [%{"id" => ^id, "paired" => true, "pairing_expires_at" => nil}]} =
             ctx.owner |> recycle() |> get(ctx.admin) |> json_response(200)

    # Renewal keeps the screen.
    assert %{"token" => renewed} =
             ctx.tv |> with_token(token) |> post("/api/box-screen/token") |> json_response(200)

    assert ctx.tv |> with_token(renewed) |> get("/api/box-screen/today") |> json_response(200)

    # A new code moves the screen: the first TV stops once another pairs.
    %{"pairing_code" => %{"code" => second}} =
      ctx.owner |> send_json(:post, "#{ctx.admin}/#{id}/pairing-code", %{}) |> json_response(201)

    assert ctx.tv |> with_token(token) |> get("/api/box-screen/today") |> json_response(200)
    assert %{"token" => moved} = ctx |> pair(second) |> json_response(201)

    for old <- [token, renewed] do
      assert %{"code" => "invalid_screen_token"} =
               ctx.tv |> with_token(old) |> get("/api/box-screen/today") |> json_response(401)
    end

    assert ctx.tv |> with_token(moved) |> get("/api/box-screen/today") |> json_response(200)

    # Removing the screen revokes it at once.
    assert ctx.owner |> recycle() |> delete("#{ctx.admin}/#{id}") |> response(204)

    assert %{"code" => "invalid_screen_token"} =
             ctx.tv |> with_token(moved) |> get("/api/box-screen/today") |> json_response(401)
  end

  test "an expired code does not pair", ctx do
    {_id, code} = new_screen(ctx)
    FixedBoxScreenClock.set(DateTime.add(ctx.now, 15 * 60))
    assert %{"code" => "invalid_pairing_code"} = ctx |> pair(code) |> json_response(422)
  end

  test "today: the box's day, its classes, WODs, leaderboard, bookings and focus", ctx do
    workout =
      workout_fixture(ctx.owner_user, %{
        title: "Fran",
        sections: [
          %{
            name: "For time",
            order: 1,
            scoreable: true,
            score_config: %{type: "time"},
            exercises: [%{name: "Thrusters", order: 1, prescription_value: 21}]
          }
        ]
      })

    section = hd(workout.sections)

    {:ok, kypseli} = Facility.create_location(ctx.context, %{name: "Κυψέλη"})
    {:ok, patisia} = Facility.create_location(ctx.context, %{name: "Πατήσια"})

    running = slot_fixture(workout)
    later = slot_fixture(workout)
    elsewhere = slot_fixture(workout)
    whole_box = slot_fixture(workout)
    move_class(running, DateTime.add(ctx.now, -10 * 60), kypseli.id)
    move_class(later, DateTime.add(ctx.now, 90 * 60), kypseli.id)
    move_class(elsewhere, DateTime.add(ctx.now, 30 * 60), patisia.id)
    move_class(whole_box, DateTime.add(ctx.now, 60 * 60), nil)

    anna = member("Άννα Κωνσταντίνου")
    bob = member("Βασίλης Χ.")
    cat = member("Κατερίνα")
    dan = member("Δανάη")

    {:ok, _} =
      Community.put_social_settings(%{user_id: bob.id}, bob.id, %{hide_from_members: true})

    for user <- [anna, bob] do
      {:ok, _} =
        Scheduling.submit_auto_approved_booking_with(ctx.context, user.id, running.id, %{})
    end

    {:ok, _} =
      Scheduling.submit_auto_approved_booking_with(ctx.context, dan.id, running.id, %{
        guest_name: "Φίλη της Δανάης",
        kind: "guest",
        entitlement_allowance: "guest_passes"
      })

    log = fn user, time ->
      put_bearer_token(build_conn(), user)
      |> send_json(:post, "/api/org/#{ctx.slug}/me/training-log/entries", %{
        source_type: "library_workout",
        source_reference_id: workout.id,
        performed_at: ctx.now |> DateTime.add(-60) |> DateTime.to_iso8601(),
        timezone: ctx.zone,
        idempotency_key: "tv-" <> Ecto.UUID.generate(),
        section_scores: [%{section_id: section.id, value: time}]
      })
      |> json_response(201)
    end

    opt_in = fn user ->
      put_bearer_token(build_conn(), user)
      |> send_json(:post, "/api/org/#{ctx.slug}/landing/leaderboard-opt-in", %{opted_in: true})
      |> json_response(200)
    end

    log.(anna, "4:10")
    log.(bob, "3:01")
    %{"entry" => %{"id" => private_id}} = log.(cat, "2:59")
    log.(dan, "3:30")
    Enum.each([anna, bob, cat], opt_in)

    Repo.query!("UPDATE training_log_entries SET journal_visibility = 'private' WHERE id = $1", [
      Ecto.UUID.dump!(private_id)
    ])

    {id, code} = new_screen(ctx, %{name: "Κυψέλη TV", location_id: kypseli.id})
    %{"token" => token} = ctx |> pair(code) |> json_response(201)

    today = fn ->
      ctx.tv |> with_token(token) |> get("/api/box-screen/today") |> json_response(200)
    end

    body = today.()

    assert body["date"] ==
             ctx.now |> DateTime.shift_zone!(ctx.zone) |> DateTime.to_date() |> Date.to_iso8601()

    assert body["time_zone"] == ctx.zone
    assert %{"name" => "Κυψέλη TV", "branch" => %{"name" => "Κυψέλη"}} = body["screen"]

    # Its branch and whole-box classes, in order; never another branch's.
    assert Enum.map(body["classes"], & &1["id"]) == [running.id, whole_box.id, later.id]

    assert [%{"id" => workout_id, "title" => "Fran", "body" => %{"kind" => "structured"}}] =
             body["workouts"]

    assert workout_id == workout.id

    # First names only; hidden people and guests are only counted.
    running_view = hd(body["classes"])

    assert %{"count" => 3, "names" => ["Άννα"], "unnamed" => 2, "capacity" => 10} =
             running_view["bookings"]

    # Opted in, not hidden, not journal-private.
    assert [
             %{
               "workout_id" => ^workout_id,
               "score" => %{"score_type" => "time"},
               "entries" => entries
             }
           ] =
             body["leaderboards"]

    assert [%{"rank" => 1, "name" => "Άννα", "value" => "4:10"}] = entries

    refute inspect(body) =~ "Κωνσταντίνου"
    refute inspect(body) =~ anna.id

    running_id = running.id

    assert %{"source" => "auto", "view" => "timer", "slot_id" => ^running_id, "until" => nil} =
             body["focus"]

    # Staff pin the leaderboard; the TV says who pinned it nowhere.
    until = ctx.now |> DateTime.add(1200) |> DateTime.to_iso8601()

    ctx.owner
    |> send_json(:put, "#{ctx.admin}/#{id}/override", %{view: "leaderboard", until: until})
    |> json_response(200)

    assert %{"source" => "staff", "view" => "leaderboard", "slot_id" => nil, "until" => _} =
             today.()["focus"]

    later_id = later.id

    ctx.owner
    |> send_json(:put, "#{ctx.admin}/#{id}/override", %{view: "class", slot_id: later.id})
    |> json_response(200)

    assert %{"source" => "staff", "view" => "class", "slot_id" => ^later_id} = today.()["focus"]

    # Another branch's class cannot be pinned on this screen.
    assert %{"code" => "invalid_screen_override"} =
             ctx.owner
             |> send_json(:put, "#{ctx.admin}/#{id}/override", %{
               view: "class",
               slot_id: elsewhere.id
             })
             |> json_response(422)

    # «Επιστροφή στο αυτόματο».
    ctx.owner |> recycle() |> delete("#{ctx.admin}/#{id}/override") |> json_response(200)
    assert %{"source" => "auto", "view" => "timer"} = today.()["focus"]

    # 55 minutes later the class has ended: its results, for 30 minutes.
    FixedBoxScreenClock.set(DateTime.add(ctx.now, 55 * 60))

    assert %{"source" => "auto", "view" => "results", "slot_id" => ^running_id} =
             today.()["focus"]

    # The class timer: this screen's classes only.
    assert %{"class" => %{"id" => ^running_id}, "timer" => %{"status" => "ready"}} =
             ctx.tv
             |> with_token(token)
             |> get("/api/box-screen/classes/#{running.id}/timer")
             |> json_response(200)

    assert ctx.tv
           |> with_token(token)
           |> get("/api/box-screen/classes/#{elsewhere.id}/timer")
           |> json_response(404)
  end
end
