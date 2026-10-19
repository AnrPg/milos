defmodule MilosTrainingWeb.PhaseBControllerTest do
  use MilosTrainingWeb.ConnCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.{Finance, Organizations, Repo}

  import MilosTraining.TestFixtures

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:milos_training, Oban), :testing, :manual)}
    )

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)

    %{
      admin: admin,
      admin_conn: put_bearer_token(conn, admin),
      base: "/api/org/#{Organizations.legacy_organization_slug()}"
    }
  end

  defp member(conn) do
    user = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user)
    {user, put_bearer_token(conn, user)}
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  test "class types carry credit cost and kind; scheduling defaults include booking rules", %{
    admin_conn: admin_conn,
    base: base
  } do
    class_type =
      admin_conn
      |> send_json(:post, "#{base}/admin/class-types", %{
        name: "Open day",
        credit_cost: 2,
        kind: "event"
      })
      |> json_response(201)
      |> Map.fetch!("class_type")

    assert %{"credit_cost" => 2, "kind" => "event"} = class_type

    settings =
      admin_conn
      |> send_json(:patch, "#{base}/admin/settings", %{
        scheduling: %{default_booking_window_days: 14, default_cancellation_cutoff_hours: 6}
      })
      |> json_response(200)

    assert %{"default_booking_window_days" => 14, "default_cancellation_cutoff_hours" => 6} =
             settings["scheduling"]
  end

  test "class types carry a level and audiences for the schedule filters", %{
    admin_conn: admin_conn,
    base: base
  } do
    default =
      admin_conn
      |> send_json(:post, "#{base}/admin/class-types", %{name: "WOD"})
      |> json_response(201)
      |> Map.fetch!("class_type")

    assert %{"level" => "all_levels", "audiences" => []} = default

    tagged =
      admin_conn
      |> send_json(:patch, "#{base}/admin/class-types/#{default["id"]}", %{
        name: "Ladies foundations",
        level: "beginner",
        audiences: ["women_only"]
      })
      |> json_response(200)
      |> Map.fetch!("class_type")

    assert %{"level" => "beginner", "audiences" => ["women_only"]} = tagged

    admin_conn
    |> send_json(:post, "#{base}/admin/class-types", %{name: "Bad", level: "expert"})
    |> json_response(422)

    admin_conn
    |> send_json(:post, "#{base}/admin/class-types", %{name: "Bad", audiences: ["pets"]})
    |> json_response(422)

    schedule =
      admin_conn
      |> recycle()
      |> get("#{base}/schedule?start_date=#{Date.utc_today()}&days=7")
      |> json_response(200)

    assert %{"level" => "beginner", "audiences" => ["women_only"]} =
             Enum.find(schedule["class_types"], &(&1["id"] == default["id"]))
  end

  test "admins look up addresses and pins for a location", %{
    conn: conn,
    admin_conn: admin_conn,
    base: base
  } do
    assert [%{"neighbourhood" => "Κυψέλη", "latitude" => lat}] =
             admin_conn
             |> get("#{base}/admin/geocode?q=#{URI.encode("Φωκίωνος Νέγρη 12")}&language=el")
             |> json_response(200)
             |> Map.fetch!("places")

    assert is_float(lat)

    assert %{"places" => []} =
             admin_conn |> recycle() |> get("#{base}/admin/geocode?q=ab") |> json_response(200)

    assert %{"code" => "geocoder_unavailable"} =
             admin_conn |> recycle() |> get("#{base}/admin/geocode?q=down") |> json_response(503)

    assert %{"place" => %{"address" => "Φωκίωνος Νέγρη 12", "latitude" => 38.0001}} =
             admin_conn
             |> recycle()
             |> get("#{base}/admin/geocode/reverse?latitude=38.0001&longitude=23.73")
             |> json_response(200)

    assert %{"place" => nil} =
             admin_conn
             |> recycle()
             |> get("#{base}/admin/geocode/reverse?latitude=10&longitude=10")
             |> json_response(200)

    long = "https://www.google.com/maps/place/Box/@37.99,23.70,15z/data=!3d38.0012!4d23.7351"

    assert %{"place" => %{"latitude" => 38.0012, "neighbourhood" => "Κυψέλη"}} =
             admin_conn
             |> recycle()
             |> get("#{base}/admin/geocode/link?url=#{URI.encode_www_form(long)}")
             |> json_response(200)

    assert %{"place" => %{"longitude" => 23.7345526}} =
             admin_conn
             |> recycle()
             |> get(
               "#{base}/admin/geocode/link?url=#{URI.encode_www_form("https://maps.app.goo.gl/kypseli")}"
             )
             |> json_response(200)

    for bad <- ["https://evil.example/@38,23", "https://maps.app.goo.gl/unknown", "not a link"] do
      admin_conn
      |> recycle()
      |> get("#{base}/admin/geocode/link?url=#{URI.encode_www_form(bad)}")
      |> json_response(422)
    end

    {_user, member_conn} = member(conn)

    member_conn
    |> get("#{base}/admin/geocode?q=#{URI.encode("Νέγρη")}")
    |> json_response(403)
  end

  test "locations, waitlists, guests and check-ins through the API", %{
    conn: conn,
    admin: admin,
    admin_conn: admin_conn,
    base: base
  } do
    location =
      admin_conn
      |> send_json(:post, "#{base}/admin/locations", %{name: "Harbour", address: "Pier 4"})
      |> json_response(201)
      |> Map.fetch!("location")

    workout = workout_fixture(admin)
    class_type = class_type_fixture(%{name: "Harbour WOD"})

    slot =
      admin_conn
      |> send_json(:post, "#{base}/admin/schedule/slots", %{
        master_workout_id: workout.id,
        class_type_id: class_type.id,
        location_id: location["id"],
        scheduled_at: DateTime.utc_now() |> DateTime.add(7200) |> DateTime.truncate(:second),
        capacity: 1,
        auto_approve: true,
        booking_timeout_minutes: 30
      })
      |> json_response(201)
      |> Map.fetch!("slot")

    assert slot["location_id"] == location["id"]

    {_first, first_conn} = member(conn)
    {_second, second_conn} = member(conn)

    first_conn
    |> send_json(:post, "#{base}/bookings", %{slot_id: slot["id"]})
    |> json_response(201)

    assert %{"code" => "already_booked"} =
             first_conn
             |> send_json(:post, "#{base}/bookings/waitlist", %{slot_id: slot["id"]})
             |> json_response(409)

    entry =
      second_conn
      |> send_json(:post, "#{base}/bookings/waitlist", %{slot_id: slot["id"]})
      |> json_response(201)
      |> Map.fetch!("booking")

    assert entry["status"] == "waitlisted"

    schedule =
      second_conn
      |> recycle()
      |> get("#{base}/schedule?start_date=#{Date.utc_today()}&days=7")
      |> json_response(200)

    assert Enum.any?(schedule["locations"], &(&1["id"] == location["id"]))
    listed = Enum.find(schedule["slots"], &(&1["id"] == slot["id"]))
    assert listed["waitlist_count"] == 1

    assert %{"status" => "waitlisted", "waitlist_position" => 1} =
             listed["current_user_booking"]

    assert %{"code" => "slot_full"} =
             first_conn
             |> send_json(:post, "#{base}/bookings/guests", %{
               slot_id: slot["id"],
               guest_name: "Anna"
             })
             |> json_response(409)

    assert %{"ok" => true, "late_cancellation" => false} =
             second_conn
             |> recycle()
             |> delete("#{base}/bookings/#{entry["id"]}")
             |> json_response(200)

    assert [%{"name" => "Harbour"}] =
             first_conn
             |> recycle()
             |> get("#{base}/locations")
             |> json_response(200)
             |> Map.fetch!("locations")

    check_in =
      first_conn
      |> send_json(:post, "#{base}/check-ins", %{location_id: location["id"]})
      |> json_response(201)
      |> Map.fetch!("check_in")

    assert check_in["source"] == "self"

    assert [%{"id" => listed_id}] =
             admin_conn
             |> recycle()
             |> get("#{base}/admin/check-ins?date=#{check_in["checked_in_on"]}")
             |> json_response(200)
             |> Map.fetch!("check_ins")

    assert listed_id == check_in["id"]

    assert %{"location" => %{"archived_at" => archived_at}} =
             admin_conn
             |> send_json(:post, "#{base}/admin/locations/#{location["id"]}/archive", %{})
             |> json_response(200)

    assert archived_at
  end

  test "admins freeze packages that include freezes and get coded errors otherwise", %{
    conn: conn,
    admin_conn: admin_conn,
    base: base
  } do
    {user, _member_conn} = member(conn)

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, package} =
      Finance.create_package(%{
        name: "Freezable",
        package_type: "membership",
        fields: %{"perks.freeze_days_per_year" => 10}
      })

    {:ok, _subscription} = Finance.assign_package(membership.id, package.id, %{})
    today = Date.utc_today()

    assert %{"code" => "freeze_allowance_exceeded"} =
             admin_conn
             |> send_json(:post, "#{base}/admin/users/#{user.id}/freezes", %{
               starts_on: today,
               ends_on: Date.add(today, 20),
               reason: "Long trip"
             })
             |> json_response(422)

    freeze =
      admin_conn
      |> send_json(:post, "#{base}/admin/users/#{user.id}/freezes", %{
        starts_on: Date.add(today, 1),
        ends_on: Date.add(today, 3),
        reason: "Injury"
      })
      |> json_response(201)
      |> Map.fetch!("freeze")

    # A recurring membership has no end date to move.
    assert freeze["extension_days"] == 0

    assert [%{"id" => id}] =
             admin_conn
             |> recycle()
             |> get("#{base}/admin/users/#{user.id}/freezes")
             |> json_response(200)
             |> Map.fetch!("freezes")

    assert id == freeze["id"]

    assert %{"freeze" => %{"cancelled_at" => cancelled_at}} =
             admin_conn
             |> send_json(:post, "#{base}/admin/users/#{user.id}/freezes/#{id}/cancel", %{
               reason: "Recovered"
             })
             |> json_response(200)

    assert cancelled_at
  end
end
