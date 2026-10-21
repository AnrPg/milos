defmodule PaleeWeb.ClassCheckInTest do
  @moduledoc "TD-105: a member checks in to a class they booked, inside its window."

  use PaleeWeb.ConnCase, async: false

  alias Palee.{Organizations, Repo, Scheduling}

  import Palee.TestFixtures

  defp legacy_tenant_context(actor, role \\ nil) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  defp move_slot(slot, starts_at) do
    Repo.query!("UPDATE scheduled_classes SET scheduled_at = $1 WHERE id = $2", [
      starts_at,
      Ecto.UUID.dump!(slot.id)
    ])
  end

  setup do
    admin = admin_fixture()
    member = user_fixture()
    legacy_tenant_context(admin, :owner)
    context = legacy_tenant_context(member)
    workout = workout_fixture(admin, %{title: "Check-in WOD"})
    slot = slot_fixture(workout, %{auto_approve: true})
    {:ok, booking} = Scheduling.submit_auto_approved_booking(context, member.id, slot.id)

    %{
      member: member,
      slot: slot,
      booking: booking,
      path: "/api/org/#{Organizations.legacy_organization_slug()}/bookings/#{booking.id}/check-in"
    }
  end

  test "checks in inside the window, once, and the schedule shows it", ctx do
    %{conn: conn, member: member, slot: slot, path: path} = ctx
    assert ctx.booking.status in [:approved, "approved"]

    assert %{"code" => "check_in_not_open"} =
             conn |> put_bearer_token(member) |> post(path) |> json_response(409)

    move_slot(slot, DateTime.utc_now() |> DateTime.add(600) |> DateTime.truncate(:second))

    assert %{"attendance" => %{"status" => "attended"} = first} =
             build_conn() |> put_bearer_token(member) |> post(path) |> json_response(200)

    assert %{"attendance" => again} =
             build_conn() |> put_bearer_token(member) |> post(path) |> json_response(200)

    assert again["marked_at"] == first["marked_at"]

    schedule =
      build_conn()
      |> put_bearer_token(member)
      |> get("/api/org/#{Organizations.legacy_organization_slug()}/schedule")
      |> json_response(200)

    assert %{"current_user_booking" => %{"attendance_status" => "attended"} = booking} =
             Enum.find(schedule["slots"], &(&1["id"] == slot.id))

    assert booking["check_in_opens_at"]
  end

  test "refuses after the class ended and for someone else's booking", ctx do
    %{conn: conn, member: member, slot: slot, path: path} = ctx
    move_slot(slot, DateTime.utc_now() |> DateTime.add(-3 * 3600) |> DateTime.truncate(:second))

    assert %{"code" => "check_in_closed"} =
             conn |> put_bearer_token(member) |> post(path) |> json_response(409)

    other = user_fixture()
    legacy_tenant_context(other)
    build_conn() |> put_bearer_token(other) |> post(path) |> json_response(404)
  end
end
