defmodule PaleeWeb.ViewerTimeZoneTest do
  @moduledoc """
  ADR-179: one canonical clock (UTC), read on the organiser's zone and, when
  the reader's differs, on theirs too.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Community.Event
  alias Palee.{Identity, Notifications, Organizations, Repo}
  alias Palee.Notifications.Notification

  setup do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    owner = admin_fixture(%{nickname: "viewer_tz_owner"})
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    %{organization: organization, owner: owner}
  end

  defp put_json(conn, user, path, body) do
    conn
    |> put_bearer_token(user)
    |> put_req_header("content-type", "application/json")
    |> put(path, Jason.encode!(body))
  end

  defp confirm_gym_zone(conn, owner, zone) do
    conn
    |> put_json(
      owner,
      "/api/org/#{Organizations.legacy_organization_slug()}/admin/settings/time-zone",
      %{timezone: zone, source: "confirmed"}
    )
    |> json_response(200)
  end

  test "a device reports its zone; UTC says nothing and unknown zones are refused", ctx do
    %{conn: conn, owner: owner} = ctx

    assert %{"time_zone" => "Europe/London"} =
             conn
             |> put_json(owner, "/api/me/time-zone", %{time_zone: "Europe/London"})
             |> json_response(200)

    assert %{"time_zone" => "Europe/London"} =
             conn
             |> recycle()
             |> put_bearer_token(owner)
             |> get("/api/auth/me")
             |> json_response(200)

    assert %{"time_zone" => "Europe/London"} =
             conn
             |> recycle()
             |> put_json(owner, "/api/me/time-zone", %{time_zone: "Etc/UTC"})
             |> json_response(200)

    assert conn
           |> recycle()
           |> put_json(owner, "/api/me/time-zone", %{time_zone: "Mars/Olympus"})
           |> json_response(422)

    assert Identity.find_by_id(owner.id).time_zone == "Europe/London"
  end

  test "memberships carry each gym's zone", ctx do
    %{conn: conn, owner: owner, organization: organization} = ctx
    confirm_gym_zone(conn, owner, "Asia/Tokyo")

    memberships =
      conn
      |> recycle()
      |> put_bearer_token(owner)
      |> get("/api/memberships")
      |> json_response(200)

    assert %{"organization" => %{"timezone" => "Asia/Tokyo"}} =
             Enum.find(memberships, &(&1["organization"]["id"] == organization.id))
  end

  test "a push names the gym's clock and adds the reader's own time when theirs differs", ctx do
    %{conn: conn, owner: owner, organization: organization} = ctx
    confirm_gym_zone(conn, owner, "Europe/Athens")
    {:ok, _} = Identity.update_time_zone(owner.id, "Europe/London")

    Notifications.process_event("appointment_booked", %{
      user_id: owner.id,
      organization_id: organization.id,
      slot_id: Ecto.UUID.generate(),
      kind: "personal_training",
      starts_at: ~U[2026-10-24 16:00:00Z],
      client_nickname: "Nikos"
    })

    assert %{payload: %{"body" => body, "starts_when" => "24/10 19:00 Athens · 17:00 your time"}} =
             Repo.get_by!(Notification, user_id: owner.id, type: :appointment_booked)

    assert body =~ "24/10 19:00 Athens · 17:00 your time"
    refute body =~ "2026-10-24T"
  end

  test "a reader on the gym's clock gets the plain time", ctx do
    %{conn: conn, owner: owner, organization: organization} = ctx
    confirm_gym_zone(conn, owner, "Europe/Athens")
    {:ok, _} = Identity.update_time_zone(owner.id, "Europe/Athens")

    Notifications.process_event("appointment_cancelled", %{
      user_id: owner.id,
      organization_id: organization.id,
      slot_id: Ecto.UUID.generate(),
      kind: "personal_training",
      starts_at: ~U[2026-10-24 16:00:00Z]
    })

    assert %{payload: %{"starts_when" => "24/10 19:00"}} =
             Repo.get_by!(Notification, user_id: owner.id, type: :appointment_cancelled)
  end

  test "an event held away keeps its own zone; unknown zones are refused" do
    assert Event.time_zone(%{time_zone: "America/New_York"}, "Europe/Athens") ==
             "America/New_York"

    assert Event.time_zone(%{time_zone: nil}, "Europe/Athens") == "Europe/Athens"

    attrs = %{
      club_id: Ecto.UUID.generate(),
      title: "Comp",
      starts_at: ~U[2026-10-24 16:00:00Z],
      ends_at: ~U[2026-10-24 18:00:00Z],
      place_name: "Madison Square",
      time_zone: "Mars/Olympus"
    }

    assert %{errors: errors} = Event.create_changeset(attrs)
    assert Keyword.has_key?(errors, :time_zone)

    assert %{valid?: true, changes: %{time_zone: "America/New_York"}} =
             Event.create_changeset(%{attrs | time_zone: "America/New_York"})

    refute Map.has_key?(Event.create_changeset(%{attrs | time_zone: " "}).changes, :time_zone)
  end
end
