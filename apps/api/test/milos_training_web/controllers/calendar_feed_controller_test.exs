defmodule MilosTrainingWeb.CalendarFeedControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Identity, Scheduling}

  import MilosTraining.TestFixtures

  test "authenticated users can fetch signed links and public calendar feed", %{conn: conn} do
    admin = admin_fixture(%{nickname: "calendar_admin"})
    member = user_fixture(%{nickname: "calendar_member"})
    workout = workout_fixture(admin, %{title: "Calendar Burner", type: "crossfit"})
    slot = slot_fixture(workout)

    assert {:ok, _booking} =
             Scheduling.submit_booking(member.id, slot.id, slot.booking_timeout_minutes)

    links =
      conn
      |> put_bearer_token(member)
      |> get("/api/calendar/export-links")
      |> json_response(200)

    assert links["https_url"] =~ "/api/calendar/feed.ics?token="
    assert links["webcal_url"] =~ "webcal://"
    assert links["download_url"] =~ "download=1"
    assert links["help"]["google"] =~ "Google Calendar"

    feed_response =
      conn
      |> recycle()
      |> get("/api/calendar/feed.ics", %{token: links["token"]})

    assert response(feed_response, 200) =~ "BEGIN:VCALENDAR"
    assert response(feed_response, 200) =~ "SUMMARY:Class: CrossFit"
  end

  test "calendar feed rejects invalid tokens", %{conn: conn} do
    conn = get(conn, "/api/calendar/feed.ics", %{token: "invalid"})
    assert json_response(conn, 401)
  end

  test "calendar links and feed system copy use the recipient locale", %{conn: conn} do
    admin = admin_fixture(%{nickname: "calendar_locale_admin"})
    member = user_fixture(%{nickname: "calendar_locale_member"})
    assert {:ok, member} = Identity.update_profile(member.id, %{preferred_locale: "el"})
    workout = workout_fixture(admin, %{title: "Author supplied title", type: "crossfit"})
    slot = slot_fixture(workout)

    assert {:ok, _booking} =
             Scheduling.submit_booking(member.id, slot.id, slot.booking_timeout_minutes)

    links =
      conn
      |> put_bearer_token(member)
      |> get("/api/calendar/export-links")
      |> json_response(200)

    assert links["help"]["google"] =~ "Ημερολόγιο Google"

    feed =
      conn
      |> recycle()
      |> get("/api/calendar/feed.ics", %{token: links["token"]})
      |> response(200)

    assert feed =~ "SUMMARY:Κατηγορία: CrossFit"
  end

  test "regenerating calendar links revokes prior feed tokens", %{conn: conn} do
    member = user_fixture(%{nickname: "calendar_regen_member"})

    first_links =
      conn
      |> put_bearer_token(member)
      |> get("/api/calendar/export-links")
      |> json_response(200)

    regenerated_links =
      conn
      |> recycle()
      |> put_bearer_token(member)
      |> post("/api/calendar/export-links/regenerate")
      |> json_response(200)

    refute regenerated_links["token"] == first_links["token"]

    revoked_response =
      conn
      |> recycle()
      |> get("/api/calendar/feed.ics", %{token: first_links["token"]})

    assert json_response(revoked_response, 401)

    active_response =
      conn
      |> recycle()
      |> get("/api/calendar/feed.ics", %{token: regenerated_links["token"]})

    assert response(active_response, 200) =~ "BEGIN:VCALENDAR"
  end
end
