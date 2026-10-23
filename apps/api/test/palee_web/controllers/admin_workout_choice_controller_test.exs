defmodule PaleeWeb.AdminWorkoutChoiceControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Organizations, Repo}
  alias Palee.TimeZones.ZonedTime

  import Palee.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture(%{nickname: "choices_admin"})
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)

    %{conn: put_bearer_token(conn, admin), admin: admin, organization: organization}
  end

  defp path(suffix),
    do: "/api/org/#{Organizations.legacy_organization_slug()}/admin/workouts/choices#{suffix}"

  defp ids(list), do: Enum.map(list, & &1["id"])

  test "searches published library WODs by title words, type and page", %{
    conn: conn,
    admin: admin
  } do
    fran = workout_fixture(admin, %{title: "Fran benchmark", type: :crossfit})
    _murph = workout_fixture(admin, %{title: "Murph", type: :crossfit})
    squat = workout_fixture(admin, %{title: "Back squat 5x5", type: :strength})

    assert %{"workouts" => [found], "has_more" => false} =
             json_response(get(conn, path("?q=FRAN%20bench")), 200)

    assert found["id"] == fran.id
    assert found["title"] == "Fran benchmark"
    refute Map.has_key?(found, "sections")

    assert ids(json_response(get(conn, path("?type=strength")), 200)["workouts"]) == [squat.id]
    assert json_response(get(conn, path("?q=100%25")), 200)["workouts"] == []

    page = json_response(get(conn, path("?limit=2")), 200)
    assert length(page["workouts"]) == 2
    assert page["has_more"] == true
    assert page["next_offset"] == 2
    rest = json_response(get(conn, path("?limit=2&offset=2")), 200)
    assert rest["has_more"] == false

    assert MapSet.new(ids(page["workouts"]) ++ ids(rest["workouts"])) ==
             MapSet.new(ids(json_response(get(conn, path("")), 200)["workouts"]))
  end

  test "suggests the day's WOD, recent ones for the class type, then the newest", %{
    conn: conn,
    admin: admin,
    organization: organization
  } do
    zone = Organizations.organization_timezone(organization.id)
    # Classes can only be created in the future: suggest for a day ahead.
    day = Date.add(gym_today(), 10)
    noon = fn date -> ZonedTime.to_utc(date, ~T[12:00:00], zone) end

    class_type = class_type_fixture(%{name: "CrossFit"})
    other_type = class_type_fixture(%{name: "Lifting"})
    todays = workout_fixture(admin, %{title: "Today's WOD"})
    recent = workout_fixture(admin, %{title: "Last week"})
    other = workout_fixture(admin, %{title: "Lifting only"})
    newest = workout_fixture(admin, %{title: "Fresh"})

    slot_fixture(todays, %{class_type_id: class_type.id, scheduled_at: noon.(day)})
    slot_fixture(todays, %{class_type_id: other_type.id, scheduled_at: noon.(day)})
    slot_fixture(recent, %{class_type_id: class_type.id, scheduled_at: noon.(Date.add(day, -6))})
    slot_fixture(other, %{class_type_id: other_type.id, scheduled_at: noon.(Date.add(day, -2))})

    body =
      json_response(get(conn, path("/suggested?date=#{day}&class_type_id=#{class_type.id}")), 200)

    assert body["date"] == Date.to_iso8601(day)
    assert ids(body["same_day"]) == [todays.id]
    assert ids(body["recent"]) == [recent.id]
    assert newest.id in ids(body["newest"])
    refute todays.id in ids(body["newest"])

    assert json_response(get(conn, path("/suggested?date=nope")), 400)["code"] == "invalid_date"
  end
end
