defmodule PaleeWeb.ClassesWithoutWodTest do
  @moduledoc "ADR-176: classes created before their WOD."

  use PaleeWeb.ConnCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Ecto.Query
  import Palee.TestFixtures

  alias Oban.Testing
  alias Palee.Application.ClassWorkoutAlerts
  alias Palee.Notifications.Notification
  alias Palee.{Organizations, Repo}

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture(%{nickname: "nowod_admin"})
    coach = user_fixture(%{nickname: "nowod_coach"})
    member = user_fixture(%{nickname: "nowod_member"})
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(coach, :coach)
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member)

    %{
      organization: organization,
      admin: admin,
      coach: coach,
      member: member,
      workout: workout_fixture(admin, %{title: "Fran"}),
      class_type: class_type_fixture(%{name: "CrossFit"})
    }
  end

  defp path(suffix), do: "/api/org/#{Organizations.legacy_organization_slug()}#{suffix}"

  defp json_conn(conn, user),
    do: conn |> put_bearer_token(user) |> put_req_header("content-type", "application/json")

  # Two days ahead at 18:00 Athens time, so it is always in the future.
  defp class_start do
    date = Date.add(Date.utc_today(), 2)
    date |> DateTime.new!(~T[18:00:00], "Europe/Athens") |> DateTime.shift_zone!("Etc/UTC")
  end

  defp create_draft(conn, ctx, attrs \\ %{}) do
    body =
      Map.merge(
        %{
          class_type_id: ctx.class_type.id,
          coach_user_id: ctx.coach.id,
          name: "Evening WOD",
          scheduled_at: class_start(),
          capacity: 10,
          auto_approve: true,
          booking_timeout_minutes: 30
        },
        attrs
      )

    conn
    |> json_conn(ctx.admin)
    |> post(path("/admin/schedule/slots"), Jason.encode!(body))
    |> json_response(201)
    |> Map.fetch!("slot")
  end

  defp schedule(conn, user) do
    start_at = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)
    end_at = DateTime.add(start_at, 5 * 86_400, :second)

    conn
    |> put_bearer_token(user)
    |> get(
      path(
        "/schedule?start_at=#{URI.encode_www_form(DateTime.to_iso8601(start_at))}" <>
          "&end_at=#{URI.encode_www_form(DateTime.to_iso8601(end_at))}&days=7"
      )
    )
    |> json_response(200)
    |> Map.fetch!("slots")
  end

  test "a class without a WOD is a draft only staff see until a WOD is linked", ctx do
    %{conn: conn} = ctx
    slot = create_draft(conn, ctx)
    assert slot["master_workout_id"] == nil

    assert [%{"published" => false, "workout_status" => "missing"}] =
             conn |> recycle() |> schedule(ctx.admin) |> Enum.filter(&(&1["id"] == slot["id"]))

    assert conn |> recycle() |> schedule(ctx.member) |> Enum.all?(&(&1["id"] != slot["id"]))

    booking =
      conn
      |> recycle()
      |> json_conn(ctx.member)
      |> post(path("/bookings"), Jason.encode!(%{slot_id: slot["id"]}))

    assert %{"code" => "class_not_published"} = json_response(booking, 409)

    linked =
      conn
      |> recycle()
      |> json_conn(ctx.coach)
      |> put(
        path("/admin/schedule/slots/#{slot["id"]}/workout"),
        Jason.encode!(%{master_workout_id: ctx.workout.id})
      )
      |> json_response(200)
      |> Map.fetch!("slot")

    assert is_binary(linked["master_workout_id"])

    assert [%{"published" => true, "workout_status" => "linked"}] =
             conn |> recycle() |> schedule(ctx.member) |> Enum.filter(&(&1["id"] == slot["id"]))
  end

  test "a series may be created without a WOD and its occurrences stay published", ctx do
    %{conn: conn} = ctx
    starts_on = Date.add(Date.utc_today(), 2)

    series =
      conn
      |> json_conn(ctx.admin)
      |> post(
        path("/admin/schedule/slots/series"),
        Jason.encode!(%{
          class_type_id: ctx.class_type.id,
          name: "Weekday WOD",
          duration_minutes: 60,
          timezone: "Europe/Athens",
          starts_on: starts_on,
          ends_on: starts_on,
          local_start_time: "18:00:00",
          weekdays: [Date.day_of_week(starts_on)],
          capacity: 10,
          auto_approve: true,
          booking_timeout_minutes: 30
        })
      )
      |> json_response(201)
      |> Map.fetch!("series")

    assert series["master_workout_id"] == nil and series["occurrence_count"] == 1

    assert [%{"published" => true, "workout_status" => "awaiting"}] =
             conn
             |> recycle()
             |> schedule(ctx.member)
             |> Enum.filter(&(&1["class_series_id"] == series["id"]))
  end

  test "a booked class keeps its WOD", ctx do
    %{conn: conn} = ctx
    slot = create_draft(conn, ctx, %{master_workout_id: ctx.workout.id})

    conn
    |> recycle()
    |> json_conn(ctx.member)
    |> post(path("/bookings"), Jason.encode!(%{slot_id: slot["id"]}))
    |> json_response(201)

    response =
      conn
      |> recycle()
      |> json_conn(ctx.admin)
      |> patch(
        path("/admin/schedule/slots/#{slot["id"]}"),
        Jason.encode!(%{
          master_workout_id: nil,
          class_type_id: ctx.class_type.id,
          scheduled_at: slot["scheduled_at"],
          capacity: 10,
          auto_approve: true,
          booking_timeout_minutes: 30
        })
      )

    assert %{"errors" => %{"master_workout_id" => [_message]}} = json_response(response, 422)
  end

  test "staff who plan the schedule and the class's coach hear at 07:00 and an hour before",
       ctx do
    %{conn: conn, organization: organization} = ctx
    slot = create_draft(conn, ctx)
    starts_at = class_start()
    context = %{organization_id: organization.id}

    alerts = fn ->
      Repo.all(
        from n in Notification,
          where: n.type == :class_workout_missing,
          select: {n.user_id, n.payload["alert"]}
      )
    end

    Testing.with_testing_mode(:inline, fn ->
      # The evening before: nothing yet.
      ClassWorkoutAlerts.sweep(context, DateTime.add(starts_at, -20, :hour))
      assert alerts.() == []

      # 07:05 Athens on the day, swept twice: one morning alert each.
      morning = DateTime.add(starts_at, -655, :minute)
      ClassWorkoutAlerts.sweep(context, morning)
      ClassWorkoutAlerts.sweep(context, DateTime.add(morning, 5, :minute))

      assert alerts.() |> Enum.sort() ==
               Enum.sort([{ctx.admin.id, "morning"}, {ctx.coach.id, "morning"}])

      # Fifty minutes before: the hour-before alert.
      ClassWorkoutAlerts.sweep(context, DateTime.add(starts_at, -50, :minute))
      assert length(alerts.()) == 4

      assert Enum.all?(alerts.(), fn {user_id, _alert} -> user_id != ctx.member.id end)
    end)

    payload =
      Repo.one!(
        from n in Notification,
          where: n.type == :class_workout_missing and n.user_id == ^ctx.admin.id,
          limit: 1,
          select: n.payload
      )

    assert payload["scheduled_class_id"] == slot["id"]
    assert payload["published"] in [false, "false"]
  end
end
