defmodule MilosTrainingWeb.CalendarFeedControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Identity, Scheduling}
  alias MilosTraining.Application.CreateRecurringClassSeries

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

  test "the feed carries only the organizations the account actually belongs to", %{conn: conn} do
    # A class exists in the legacy organization...
    legacy_admin = admin_fixture(%{nickname: "calendar_legacy_admin"})
    legacy_workout = workout_fixture(legacy_admin, %{title: "Legacy Burner", type: "crossfit"})
    legacy_slot = slot_fixture(legacy_workout)

    assert {:ok, _booking} =
             Scheduling.submit_booking(
               legacy_admin.id,
               legacy_slot.id,
               legacy_slot.booking_timeout_minutes
             )

    # ...and an unrelated account belongs only to a different gym.
    {:ok, other_org} = MilosTraining.Organizations.create_organization(%{name: "Calendar Gym B"})
    outsider = user_fixture(%{nickname: "calendar_outsider"})

    {:ok, _} =
      MilosTraining.Organizations.add_membership(%{
        organization_id: other_org.id,
        user_id: outsider.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    links =
      conn
      |> put_bearer_token(outsider)
      |> get("/api/calendar/export-links")
      |> json_response(200)

    body =
      conn
      |> recycle()
      |> get("/api/calendar/feed.ics", %{token: links["token"]})
      |> response(200)

    # Before the tenant-scoping fix the un-scoped arity resolved to the legacy
    # organization, so this class appeared in every account's feed (F-18).
    assert body =~ "BEGIN:VCALENDAR"
    refute body =~ "Legacy Burner"
    refute body =~ "SUMMARY:Class: CrossFit"
  end

  test "calendar feed rejects invalid tokens", %{conn: conn} do
    conn = get(conn, "/api/calendar/feed.ics", %{token: "invalid"})
    assert json_response(conn, 401)
  end

  test "admin feed keeps recurring classes as recurring iCalendar events", %{conn: conn} do
    admin = admin_fixture(%{nickname: "calendar_series_admin"})
    workout = workout_fixture(admin, %{title: "Series Workout"})
    class_type = class_type_fixture(%{name: "CrossFit"})
    starts_on = Date.add(Date.utc_today(), 1)
    first_occurrence_on = Date.add(starts_on, 1)
    excluded_on = Date.add(first_occurrence_on, 7)

    assert {:ok, series} =
             CreateRecurringClassSeries.call(%{
               master_workout_id: workout.id,
               class_type_id: class_type.id,
               name: "CrossFit beginners",
               duration_minutes: 75,
               timezone: "Etc/UTC",
               starts_on: starts_on,
               ends_on: Date.add(starts_on, 14),
               local_start_time: ~T[17:00:00],
               weekdays: [Date.day_of_week(first_occurrence_on)],
               excluded_dates: [excluded_on],
               capacity: 10,
               auto_approve: true,
               booking_timeout_minutes: 30
             })

    links =
      conn
      |> put_bearer_token(admin)
      |> get("/api/calendar/export-links")
      |> json_response(200)

    feed =
      conn
      |> recycle()
      |> get("/api/calendar/feed.ics", %{token: links["token"]})
      |> response(200)

    assert feed =~ "UID:class-series-#{series.id}@trainingjournal"

    assert feed =~
             "DTSTART;TZID=Etc/UTC:#{Calendar.strftime(first_occurrence_on, "%Y%m%d")}T170000"

    assert feed =~ "RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY="
    assert feed =~ "EXDATE;TZID=Etc/UTC:#{Calendar.strftime(excluded_on, "%Y%m%d")}T170000"
    assert feed =~ "DURATION:PT75M"
    assert feed =~ "SUMMARY:Class: CrossFit beginners"
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
