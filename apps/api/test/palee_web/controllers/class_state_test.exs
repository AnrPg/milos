defmodule PaleeWeb.ClassStateTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Notifications, Organizations, Repo, Scheduling}
  alias Palee.Application.SubmitBooking

  import Palee.TestFixtures

  # ADR-200 §2: pause, resume, cancel, restore and delete, for one class or,
  # by series scope and every, for the other classes of its series.

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
        capacity: 1,
        auto_approve: true,
        booking_timeout_minutes: 30
      })
      |> json_response(201)

    {:ok, context} =
      Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

    %{admin_conn: admin_conn, base: base, series_id: series["id"], context: context}
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

  defp change(%{admin_conn: conn, base: base}, slot, body),
    do: send_json(conn, :post, "#{base}/#{slot.id}/state", body)

  defp member_booking(context, slot) do
    member = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member, :member)

    {:ok, booking} =
      Scheduling.submit_auto_approved_booking_with(context, member.id, slot.id, %{})

    {member, booking}
  end

  test "pause keeps bookings and stops new ones; resume reopens", %{context: context} = ctx do
    [first | _] = classes(context, ctx.series_id)
    {_member, _booking} = member_booking(context, first)

    assert %{"changed_count" => 1, "slots" => [%{"paused_at" => paused_at}]} =
             ctx |> change(first, %{action: "pause"}) |> json_response(200)

    assert paused_at
    assert length(Scheduling.get_slot(context, first.id).bookings) == 1

    other = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(other, :member)

    assert {:error, :class_paused} = SubmitBooking.call(context, other, first.id)

    assert %{"changed_count" => 1} =
             ctx |> change(first, %{action: "resume"}) |> json_response(200)

    assert is_nil(Scheduling.get_slot(context, first.id).paused_at)
  end

  test "cancel releases every place, tells members once and can be restored",
       %{context: context} = ctx do
    [first | _] = classes(context, ctx.series_id)
    {member, _booking} = member_booking(context, first)

    assert %{"changed_count" => 1, "released_count" => 1, "slots" => [slot]} =
             ctx
             |> change(first, %{action: "cancel", reason: "Water leak"})
             |> json_response(200)

    assert slot["cancel_reason"] == "Water leak"
    assert Scheduling.get_slot(context, first.id).bookings == []

    assert [%{type: "class_cancelled", payload: payload}] =
             member.id |> Notifications.list_for_user() |> only("class_cancelled")

    assert payload["reason"] == "Water leak"

    assert %{"changed_count" => 1} =
             ctx |> change(first, %{action: "restore"}) |> json_response(200)

    restored = Scheduling.get_slot(context, first.id)
    assert is_nil(restored.cancelled_at) and is_nil(restored.cancel_reason)
    # Released bookings don't come back.
    assert restored.bookings == []
  end

  test "cancelling every upcoming class ends the series", %{context: context} = ctx do
    [first | _] = classes(context, ctx.series_id)

    assert %{"changed_count" => 6} =
             ctx
             |> change(first, %{action: "cancel", series_scope: "all"})
             |> json_response(200)

    assert Enum.all?(classes(context, ctx.series_id), &(&1.cancelled_at != nil))
    assert Scheduling.get_class_series(context, ctx.series_id).status == "ended"
  end

  test "every 2nd class in the scope", %{context: context} = ctx do
    [first | _] = classes(context, ctx.series_id)

    assert %{"changed_count" => 3} =
             ctx
             |> change(first, %{action: "pause", series_scope: "all", every: 2})
             |> json_response(200)

    assert Enum.map(classes(context, ctx.series_id), &(&1.paused_at != nil)) ==
             [true, false, true, false, true, false]

    # Only part of the series: it keeps going.
    assert Scheduling.get_class_series(context, ctx.series_id).status == "active"
  end

  test "a multi-class delete leaves booked classes alone and counts them",
       %{context: context} = ctx do
    [first, second | _] = classes(context, ctx.series_id)
    member_booking(context, second)

    assert %{"changed_count" => 5, "skipped_with_bookings" => 1, "deleted_ids" => ids} =
             ctx
             |> change(first, %{action: "delete", series_scope: "all"})
             |> json_response(200)

    refute second.id in ids
    assert [remaining] = classes(context, ctx.series_id)
    assert remaining.id == second.id
  end

  test "deleting one booked class is refused with the reason", %{context: context} = ctx do
    [first | _] = classes(context, ctx.series_id)
    member_booking(context, first)

    assert %{"code" => "class_has_bookings"} =
             ctx |> change(first, %{action: "delete"}) |> json_response(409)

    assert Scheduling.get_slot(context, first.id)
  end

  test "unknown actions and steps are refused", %{context: context} = ctx do
    [first | _] = classes(context, ctx.series_id)

    assert ctx |> change(first, %{action: "archive"}) |> json_response(422)

    assert %{"errors" => [%{"source" => %{"pointer" => "/every"}}]} =
             ctx
             |> change(first, %{action: "pause", series_scope: "all", every: 99})
             |> json_response(422)
  end

  defp only(notifications, type), do: Enum.filter(notifications, &(&1.type == type))
end
