defmodule PaleeWeb.CleaningControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Organizations, Repo}

  import Palee.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    staff = fn role ->
      user = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      put_bearer_token(conn, user)
    end

    %{
      owner: staff.(:owner),
      janitor: staff.(:janitor),
      desk: staff.(:front_desk),
      coach: staff.(:coach),
      base: "/api/org/#{Organizations.legacy_organization_slug()}/staff/cleaning"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  test "owners set areas, janitors log cleaning, front desk reviews", %{
    owner: owner,
    janitor: janitor,
    desk: desk,
    coach: coach,
    base: base
  } do
    area =
      owner
      |> send_json(:post, "#{base}/areas", %{name: "Showers", tasks: ["Floors", "Mirrors", " "]})
      |> json_response(201)
      |> Map.fetch!("area")

    assert area["tasks"] == ["Floors", "Mirrors"]
    assert janitor |> send_json(:post, "#{base}/areas", %{name: "Nope"}) |> json_response(403)
    assert coach |> recycle() |> get("#{base}/areas") |> json_response(403)

    entry =
      janitor
      |> send_json(:post, "#{base}/entries", %{area_id: area["id"]})
      |> json_response(201)
      |> Map.fetch!("entry")

    assert %{"entry" => %{"tasks_done" => ["Floors"], "finished_at" => finished}} =
             janitor
             |> send_json(:post, "#{base}/entries/#{entry["id"]}/finish", %{
               tasks_done: ["Floors", "Windows"],
               note: "Out of soap"
             })
             |> json_response(200)

    assert finished

    assert %{"code" => "cleaning_already_finished"} =
             janitor
             |> send_json(:post, "#{base}/entries/#{entry["id"]}/finish", %{})
             |> json_response(409)

    assert [%{"nickname" => _}] =
             desk
             |> recycle()
             |> get("#{base}/entries")
             |> json_response(200)
             |> Map.fetch!("entries")

    assert [%{"last_cleaned_at" => last}] =
             janitor
             |> recycle()
             |> get("#{base}/areas")
             |> json_response(200)
             |> Map.fetch!("areas")

    assert last

    assert desk
           |> send_json(:post, "#{base}/entries", %{area_id: area["id"]})
           |> json_response(403)
  end

  test "cleaning areas are spaces: the same rows in Settings › Spaces (ADR-202)", %{
    owner: owner,
    base: base
  } do
    area =
      owner
      |> send_json(:post, "#{base}/areas", %{name: "Showers", tasks: ["Floors"]})
      |> json_response(201)
      |> Map.fetch!("area")

    spaces_path = String.replace(base, "/cleaning", "/spaces")

    assert %{"spaces" => [%{"id" => id, "name" => "Showers", "tasks" => ["Floors"]}]} =
             owner |> recycle() |> get(spaces_path) |> json_response(200)

    assert id == area["id"]
  end

  test "the cleaning schedule: owners and front desk set it; janitors see today's list", %{
    owner: owner,
    janitor: janitor,
    desk: desk,
    coach: coach,
    base: base
  } do
    showers =
      owner
      |> send_json(:post, "#{base}/areas", %{name: "Showers", tasks: ["Floors"]})
      |> json_response(201)
      |> Map.fetch!("area")

    mats =
      owner
      |> send_json(:post, "#{base}/areas", %{name: "Mats"})
      |> json_response(201)
      |> Map.fetch!("area")

    owner |> send_json(:post, "#{base}/areas", %{name: "Office"}) |> json_response(201)

    every_day = [1, 2, 3, 4, 5, 6, 7]

    assert %{"schedule" => %{"weekdays" => ^every_day, "times" => ["07:00:00", "21:00:00"]}} =
             desk
             |> send_json(:put, "#{base}/schedules/#{showers["id"]}", %{
               weekdays: every_day,
               times: ["21:00", "07:00"],
               comment: "Disinfect the drains"
             })
             |> json_response(200)

    assert %{"schedule" => %{"comment" => nil}} =
             owner
             |> send_json(:put, "#{base}/schedules/#{mats["id"]}", %{weekdays: every_day})
             |> json_response(200)

    assert janitor
           |> send_json(:put, "#{base}/schedules/#{mats["id"]}", %{weekdays: [1]})
           |> json_response(403)

    assert coach |> recycle() |> get("#{base}/today") |> json_response(403)

    assert owner
           |> send_json(:put, "#{base}/schedules/#{mats["id"]}", %{weekdays: [1], times: ["9"]})
           |> json_response(422)

    assert %{"schedules" => [_, _]} =
             janitor |> recycle() |> get("#{base}/schedules") |> json_response(200)

    assert %{"due" => due, "open_entries" => [], "floor_plans" => []} =
             janitor |> recycle() |> get("#{base}/today") |> json_response(200)

    assert [
             %{"name" => "Mats", "cleanings_due" => 1, "cleanings_done" => 0, "done" => false},
             %{
               "name" => "Showers",
               "comment" => "Disinfect the drains",
               "cleanings_due" => 2,
               "tasks" => ["Floors"]
             }
           ] = due

    # Ticking a space off is the cleaning log's start and finish.
    entry =
      janitor
      |> send_json(:post, "#{base}/entries", %{area_id: mats["id"]})
      |> json_response(201)
      |> Map.fetch!("entry")

    assert %{"open_entries" => [%{"id" => entry_id}]} =
             janitor |> recycle() |> get("#{base}/today") |> json_response(200)

    assert entry_id == entry["id"]

    janitor
    |> send_json(:post, "#{base}/entries/#{entry["id"]}/finish", %{tasks_done: []})
    |> json_response(200)

    assert %{"due" => [%{"name" => "Mats", "done" => true}, %{"done" => false}]} =
             janitor |> recycle() |> get("#{base}/today") |> json_response(200)

    assert owner
           |> send_json(:delete, "#{base}/schedules/#{mats["id"]}", %{})
           |> response(204)

    assert %{"due" => [%{"name" => "Showers"}]} =
             janitor |> recycle() |> get("#{base}/today") |> json_response(200)
  end
end
