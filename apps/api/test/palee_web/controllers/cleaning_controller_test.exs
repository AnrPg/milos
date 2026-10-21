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
end
