defmodule PaleeWeb.DayWorkoutsTest do
  @moduledoc "ADR-224: a WOD for a whole day, inherited by its classes."

  use PaleeWeb.ConnCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Palee.TestFixtures

  alias Palee.{Organizations, Repo, Scheduling}
  alias Palee.Scheduling.{Booking, ClassType}

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture(%{nickname: "daywod_admin"})
    member = user_fixture(%{nickname: "daywod_member"})
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member)

    %{
      organization: organization,
      admin: admin,
      member: member,
      fran: workout_fixture(admin, %{title: "Fran"}),
      grace: workout_fixture(admin, %{title: "Grace"}),
      crossfit: class_type_fixture(%{name: "CrossFit"}),
      lifting: class_type_fixture(%{name: "Weightlifting"})
    }
  end

  defp path(suffix), do: "/api/org/#{Organizations.legacy_organization_slug()}#{suffix}"

  defp json_conn(conn, user),
    do: conn |> put_bearer_token(user) |> put_req_header("content-type", "application/json")

  defp zone(ctx), do: Organizations.organization_timezone(ctx.organization.id)

  # Two gym days ahead, so every class is in the future.
  defp day(ctx), do: Date.add(Organizations.local_today(ctx.organization.id), 2)

  defp at(ctx, time, date \\ nil) do
    (date || day(ctx))
    |> DateTime.new!(time, zone(ctx))
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp create_class(conn, ctx, type, attrs \\ %{}) do
    body =
      Map.merge(
        %{
          class_type_id: type.id,
          name: "#{type.name} class",
          scheduled_at: at(ctx, ~T[18:00:00]),
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

  defp set_day(conn, ctx, workout, attrs \\ %{}) do
    conn
    |> json_conn(ctx.admin)
    |> put(
      path("/admin/schedule/day-workouts"),
      Jason.encode!(Map.merge(%{date: day(ctx), master_workout_id: workout.id}, attrs))
    )
  end

  defp schedule(conn, ctx, user) do
    date = day(ctx)

    conn
    |> put_bearer_token(user)
    |> get(path("/schedule?start_date=#{Date.add(date, -1)}&days=3"))
    |> json_response(200)
  end

  defp slot(ctx, id), do: Scheduling.get_slot(legacy_tenant_context_for(ctx), id)

  defp legacy_tenant_context_for(ctx),
    do: %{organization_id: ctx.organization.id, location_scope: :all}

  defp title(ctx, workout_id),
    do: Palee.Workouts.get_workout(legacy_tenant_context_for(ctx), workout_id).title

  test "every class of the day inherits the day's WOD, including classes created later", ctx do
    %{conn: conn} = ctx
    draft = create_class(conn, ctx, ctx.crossfit)
    assert draft["master_workout_id"] == nil

    result = conn |> set_day(ctx, ctx.fran) |> json_response(200)
    assert result["changed_count"] == 1
    assert [%{"class_type_id" => nil, "workout" => %{"title" => "Fran"}}] = result["day_workouts"]

    inherited = slot(ctx, draft["id"])
    assert inherited.day_workout_id
    assert title(ctx, inherited.master_workout_id) == "Fran"

    later =
      create_class(conn |> recycle(), ctx, ctx.lifting, %{scheduled_at: at(ctx, ~T[07:00:00])})

    assert later["day_workout_id"] == inherited.day_workout_id
    assert later["master_workout_id"] == inherited.master_workout_id

    staff_view = conn |> recycle() |> schedule(ctx, ctx.admin)
    assert [%{"local_date" => date}] = staff_view["day_workouts"]
    assert date == Date.to_iso8601(day(ctx))

    assert %{"workout_source" => "day", "published" => true, "workout_status" => "linked"} =
             Enum.find(staff_view["slots"], &(&1["id"] == draft["id"]))

    # A draft became a class members see and book.
    member_view = conn |> recycle() |> schedule(ctx, ctx.member)
    assert member_view["day_workouts"] == []
    assert Enum.any?(member_view["slots"], &(&1["id"] == draft["id"]))
  end

  test "a class type's day WOD beats the all-classes one; events only follow their type", ctx do
    %{conn: conn} = ctx
    crossfit = create_class(conn, ctx, ctx.crossfit)
    lifting = create_class(conn |> recycle(), ctx, ctx.lifting)

    seminar = class_type_fixture(%{name: "Seminar"})
    Repo.update!(Ecto.Changeset.change(Repo.get!(ClassType, seminar.id), kind: "event"))
    event = create_class(conn |> recycle(), ctx, seminar)

    conn |> recycle() |> set_day(ctx, ctx.fran) |> json_response(200)

    conn
    |> recycle()
    |> set_day(ctx, ctx.grace, %{class_type_ids: [ctx.lifting.id]})
    |> json_response(200)

    assert title(ctx, slot(ctx, crossfit["id"]).master_workout_id) == "Fran"
    assert title(ctx, slot(ctx, lifting["id"]).master_workout_id) == "Grace"
    assert slot(ctx, event["id"]).master_workout_id == nil
  end

  test "a class's own WOD is kept, previewed, replaced on request and reset to the day's", ctx do
    %{conn: conn} = ctx
    own = create_class(conn, ctx, ctx.crossfit, %{master_workout_id: ctx.grace.id})

    free =
      create_class(conn |> recycle(), ctx, ctx.crossfit, %{scheduled_at: at(ctx, ~T[09:00:00])})

    preview =
      conn
      |> recycle()
      |> json_conn(ctx.admin)
      |> post(
        path("/admin/schedule/day-workouts/preview"),
        Jason.encode!(%{date: day(ctx), master_workout_id: ctx.fran.id})
      )
      |> json_response(200)

    assert Enum.map(preview["inherit"], & &1["id"]) == [free["id"]]
    assert Enum.map(preview["own"], & &1["id"]) == [own["id"]]

    conn |> recycle() |> set_day(ctx, ctx.fran) |> json_response(200)
    assert title(ctx, slot(ctx, own["id"]).master_workout_id) == "Grace"
    assert slot(ctx, own["id"]).day_workout_id == nil

    reset =
      conn
      |> recycle()
      |> json_conn(ctx.admin)
      |> post(path("/admin/schedule/slots/#{own["id"]}/day-workout"))
      |> json_response(200)
      |> Map.fetch!("slot")

    assert reset["day_workout_id"]
    assert title(ctx, reset["master_workout_id"]) == "Fran"

    # Linking a WOD to the class itself overrides the day's again.
    linked =
      conn
      |> recycle()
      |> json_conn(ctx.admin)
      |> put(
        path("/admin/schedule/slots/#{own["id"]}/workout"),
        Jason.encode!(%{master_workout_id: ctx.grace.id})
      )
      |> json_response(200)
      |> Map.fetch!("slot")

    assert linked["day_workout_id"] == nil

    conn |> recycle() |> set_day(ctx, ctx.fran, %{replace_own: true}) |> json_response(200)
    assert slot(ctx, own["id"]).day_workout_id
  end

  test "removing the day WOD clears inherited WODs, except on a booked standalone class", ctx do
    %{conn: conn} = ctx
    free = create_class(conn, ctx, ctx.crossfit)

    booked =
      create_class(conn |> recycle(), ctx, ctx.crossfit, %{scheduled_at: at(ctx, ~T[10:00:00])})

    [rule] =
      conn
      |> recycle()
      |> set_day(ctx, ctx.fran)
      |> json_response(200)
      |> Map.fetch!("day_workouts")

    Repo.insert!(%Booking{
      organization_id: ctx.organization.id,
      scheduled_class_id: booked["id"],
      user_id: ctx.member.id,
      status: :approved
    })

    result =
      conn
      |> recycle()
      |> put_bearer_token(ctx.admin)
      |> delete(path("/admin/schedule/day-workouts/#{rule["id"]}"))
      |> json_response(200)

    assert result["changed_count"] == 2
    assert slot(ctx, free["id"]).master_workout_id == nil

    kept = slot(ctx, booked["id"])
    assert kept.master_workout_id
    assert kept.day_workout_id == nil

    assert conn
           |> recycle()
           |> json_conn(ctx.admin)
           |> post(path("/admin/schedule/slots/#{free["id"]}/day-workout"))
           |> json_response(409)
           |> Map.fetch!("code") == "no_day_workout"
  end

  test "a class moved off the day loses the inherited WOD; one moved onto it gains it", ctx do
    %{conn: conn} = ctx
    moved_off = create_class(conn, ctx, ctx.crossfit)
    other_day = Date.add(day(ctx), 1)

    moved_on =
      create_class(conn |> recycle(), ctx, ctx.crossfit, %{
        scheduled_at: at(ctx, ~T[18:00:00], other_day)
      })

    conn |> recycle() |> set_day(ctx, ctx.fran) |> json_response(200)
    assert slot(ctx, moved_off["id"]).day_workout_id
    assert slot(ctx, moved_on["id"]).master_workout_id == nil

    move = fn slot_id, scheduled_at ->
      current = slot(ctx, slot_id)

      conn
      |> recycle()
      |> json_conn(ctx.admin)
      |> patch(
        path("/admin/schedule/slots/#{slot_id}"),
        Jason.encode!(%{
          class_type_id: current.class_type_id,
          name: current.name,
          duration_minutes: current.duration_minutes,
          master_workout_id: current.master_workout_id,
          scheduled_at: scheduled_at,
          capacity: current.capacity,
          auto_approve: current.auto_approve,
          booking_timeout_minutes: current.booking_timeout_minutes
        })
      )
      |> json_response(200)
      |> Map.fetch!("slot")
    end

    assert %{"master_workout_id" => nil} =
             move.(moved_off["id"], at(ctx, ~T[18:00:00], other_day))

    assert %{"day_workout_id" => rule_id} = move.(moved_on["id"], at(ctx, ~T[19:00:00]))
    assert rule_id
  end

  test "a day WOD for a past day is refused", ctx do
    %{conn: conn} = ctx
    yesterday = Date.add(Organizations.local_today(ctx.organization.id), -1)

    assert conn
           |> set_day(ctx, ctx.fran, %{date: yesterday})
           |> json_response(422)
           |> Map.fetch!("code") == "day_in_the_past"
  end

  test "a new series inherits the day WOD on its days", ctx do
    %{conn: conn} = ctx
    conn |> set_day(ctx, ctx.fran) |> json_response(200)

    series =
      conn
      |> recycle()
      |> json_conn(ctx.admin)
      |> post(
        path("/admin/schedule/slots/series"),
        Jason.encode!(%{
          class_type_id: ctx.crossfit.id,
          name: "Evening",
          duration_minutes: 60,
          timezone: zone(ctx),
          starts_on: day(ctx),
          ends_on: Date.add(day(ctx), 1),
          local_start_time: "18:00:00",
          weekdays: [Date.day_of_week(day(ctx)), Date.day_of_week(Date.add(day(ctx), 1))],
          capacity: 10,
          auto_approve: true,
          booking_timeout_minutes: 30
        })
      )
      |> json_response(201)

    series_id =
      get_in(series, ["series", "id"]) || get_in(series, ["series_list", Access.at(0), "id"])

    slots =
      conn
      |> recycle()
      |> schedule(ctx, ctx.admin)
      |> Map.fetch!("slots")
      |> Enum.filter(&(&1["class_series_id"] == series_id))

    assert [%{"workout_source" => "day"}, %{"workout_source" => nil}] =
             Enum.sort_by(slots, & &1["scheduled_at"])
  end
end
