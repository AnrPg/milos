defmodule PaleeWeb.SeriesEditScopeTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Organizations, Repo, Scheduling}

  import Palee.TestFixtures

  # ADR-200: an edit to one class of a series goes to this class only, to every
  # upcoming class (and the series), or to the classes in a date range.

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)
    class_type = class_type_fixture(%{name: "CrossFit"})
    base = "/api/org/#{Organizations.legacy_organization_slug()}/admin/schedule/slots"
    admin_conn = put_bearer_token(conn, admin)
    starts_on = Date.add(Date.utc_today(), 1)

    %{"series" => series} =
      admin_conn
      |> send_json(:post, "#{base}/series", %{
        class_type_id: class_type.id,
        name: "Morning WOD",
        duration_minutes: 60,
        timezone: "Etc/UTC",
        starts_on: starts_on,
        ends_on: Date.add(starts_on, 5),
        local_start_time: "07:00:00",
        weekdays: [1, 2, 3, 4, 5, 6, 7],
        capacity: 10,
        auto_approve: true,
        booking_timeout_minutes: 30
      })
      |> json_response(201)

    %{
      admin_conn: admin_conn,
      base: base,
      series_id: series["id"],
      starts_on: starts_on,
      context: owner_context(admin)
    }
  end

  defp owner_context(admin) do
    {:ok, context} =
      Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

    context
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp classes(context, series_id) do
    context
    |> Scheduling.list_series_slots(series_id, DateTime.utc_now())
    |> Enum.map(&Scheduling.get_slot(context, &1.id))
  end

  defp edit(%{admin_conn: conn, base: base}, slot, changes) do
    body =
      Map.merge(
        %{
          class_type_id: slot.class_type_id,
          name: slot.name,
          duration_minutes: slot.duration_minutes,
          scheduled_at: slot.scheduled_at,
          capacity: slot.capacity,
          auto_approve: slot.auto_approve,
          booking_timeout_minutes: slot.booking_timeout_minutes
        },
        changes
      )

    send_json(conn, :patch, "#{base}/#{slot.id}", body)
  end

  defp at(date, time), do: DateTime.new!(date, time, "Etc/UTC")

  test "this class only leaves the rest of the series alone", %{context: context} = ctx do
    [first, second | _] = classes(context, ctx.series_id)

    assert %{"updated_count" => 1, "slot" => %{"capacity" => 4}} =
             ctx |> edit(second, %{capacity: 4, series_scope: "this"}) |> json_response(200)

    capacities = Enum.map(classes(context, ctx.series_id), & &1.capacity)
    assert capacities == [10, 4, 10, 10, 10, 10]
    assert Scheduling.get_slot(context, first.id).capacity == 10
  end

  test "all classes take the edit, a new time on their own dates, and so does the series",
       %{context: context} = ctx do
    [_first, second | _] = all = classes(context, ctx.series_id)
    new_start = at(DateTime.to_date(second.scheduled_at), ~T[18:30:00])

    assert %{"updated_count" => 6} =
             ctx
             |> edit(second, %{
               name: "Evening WOD",
               capacity: 14,
               scheduled_at: new_start,
               series_scope: "all"
             })
             |> json_response(200)

    after_edit = classes(context, ctx.series_id)
    assert Enum.all?(after_edit, &(&1.name == "Evening WOD" and &1.capacity == 14))

    assert Enum.map(after_edit, &DateTime.to_date(&1.scheduled_at)) ==
             Enum.map(all, &DateTime.to_date(&1.scheduled_at))

    assert Enum.all?(after_edit, &(DateTime.to_time(&1.scheduled_at) == ~T[18:30:00]))

    series = Scheduling.get_class_series(context, ctx.series_id)
    assert series.name == "Evening WOD"
    assert series.capacity == 14
    assert series.local_start_time == ~T[18:30:00]
  end

  test "a date range reaches only its classes and not the series", %{context: context} = ctx do
    [first | _] = classes(context, ctx.series_id)
    from = Date.add(ctx.starts_on, 2)
    to = Date.add(ctx.starts_on, 3)

    assert %{"updated_count" => 3} =
             ctx
             |> edit(first, %{capacity: 6, series_scope: "range", range_from: from, range_to: to})
             |> json_response(200)

    capacities = Enum.map(classes(context, ctx.series_id), & &1.capacity)
    # The edited class itself, and the two classes in the range.
    assert capacities == [6, 10, 6, 6, 10, 10]
    assert Scheduling.get_class_series(context, ctx.series_id).capacity == 10
  end

  test "moving one class's date never moves the others", %{context: context} = ctx do
    [first | rest] = classes(context, ctx.series_id)
    moved = DateTime.add(first.scheduled_at, 86_400 * 10, :second)

    assert %{"updated_count" => 6} =
             ctx |> edit(first, %{scheduled_at: moved, series_scope: "all"}) |> json_response(200)

    assert Enum.map(rest, &Scheduling.get_slot(context, &1.id).scheduled_at) ==
             Enum.map(rest, & &1.scheduled_at)
  end

  test "a range needs both dates in order", %{context: context} = ctx do
    [first | _] = classes(context, ctx.series_id)

    assert %{"code" => "series_range_required"} =
             ctx
             |> edit(first, %{
               capacity: 3,
               series_scope: "range",
               range_from: Date.add(ctx.starts_on, 3),
               range_to: ctx.starts_on
             })
             |> json_response(422)

    assert Enum.all?(classes(context, ctx.series_id), &(&1.capacity == 10))
  end

  test "one class the edit cannot take leaves every class as it was", %{context: context} = ctx do
    [first, second | _] = classes(context, ctx.series_id)

    for _member <- 1..2 do
      member = user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member, :member)

      {:ok, _booking} =
        Scheduling.submit_auto_approved_booking_with(context, member.id, second.id, %{})
    end

    # One place is below the two approved bookings of the second class.
    assert ctx |> edit(first, %{capacity: 1, series_scope: "all"}) |> json_response(422)
    assert Enum.all?(classes(context, ctx.series_id), &(&1.capacity == 10))
  end
end
