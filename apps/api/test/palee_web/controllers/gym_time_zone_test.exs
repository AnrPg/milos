defmodule PaleeWeb.GymTimeZoneTest do
  @moduledoc "ADR-176: the gym's time zone, confirmed by an admin or guessed from a device."

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Organizations

  setup do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    owner = admin_fixture(%{nickname: "tz_owner"})
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    %{organization: organization, owner: owner}
  end

  defp put_zone(conn, owner, body, headers \\ []) do
    conn =
      Enum.reduce(headers, conn |> put_bearer_token(owner), fn {key, value}, acc ->
        put_req_header(acc, key, value)
      end)

    conn
    |> put_req_header("content-type", "application/json")
    |> put(
      "/api/org/#{Organizations.legacy_organization_slug()}/admin/settings/time-zone",
      Jason.encode!(body)
    )
  end

  defp onboarding_step(conn, owner) do
    conn
    |> put_bearer_token(owner)
    |> get("/api/org/#{Organizations.legacy_organization_slug()}/admin/onboarding")
    |> json_response(200)
    |> Map.fetch!("steps")
    |> Enum.find(&(&1["id"] == "timezone"))
  end

  test "a device guess applies until an admin confirms, and never after", ctx do
    %{conn: conn, owner: owner, organization: organization} = ctx

    assert %{"done" => false} = onboarding_step(conn, owner)

    assert %{"time_zone" => %{"timezone" => "Europe/Lisbon", "source" => "inferred"}} =
             conn
             |> recycle()
             |> put_zone(owner, %{timezone: "Europe/Lisbon", source: "inferred"})
             |> json_response(200)

    assert Organizations.organization_timezone(organization.id) == "Europe/Lisbon"
    assert %{"done" => false} = conn |> recycle() |> onboarding_step(owner)

    assert %{"time_zone" => %{"timezone" => "Europe/Athens", "confirmed" => true}} =
             conn
             |> recycle()
             |> put_zone(owner, %{timezone: "Europe/Athens", source: "confirmed"})
             |> json_response(200)

    assert %{"time_zone" => %{"timezone" => "Europe/Athens"}} =
             conn
             |> recycle()
             |> put_zone(owner, %{timezone: "Europe/Berlin", source: "inferred"})
             |> json_response(200)

    assert %{"done" => true} = conn |> recycle() |> onboarding_step(owner)
  end

  test "without a device zone the IP-derived zone from the edge is the guess", ctx do
    %{conn: conn, owner: owner} = ctx

    assert %{"time_zone" => %{"timezone" => "Europe/Sofia", "source" => "inferred"}} =
             conn
             |> put_zone(owner, %{timezone: nil, source: "inferred"}, [
               {"cf-timezone", "Europe/Sofia"}
             ])
             |> json_response(200)
  end

  test "an unknown zone is refused and the step cannot be skipped", ctx do
    %{conn: conn, owner: owner} = ctx

    assert %{"code" => "invalid_time_zone"} =
             conn
             |> put_zone(owner, %{timezone: "Mars/Olympus", source: "confirmed"})
             |> json_response(422)

    assert %{"code" => "time_zone_required"} =
             conn
             |> recycle()
             |> put_bearer_token(owner)
             |> put_req_header("content-type", "application/json")
             |> patch(
               "/api/org/#{Organizations.legacy_organization_slug()}/admin/onboarding",
               Jason.encode!(%{action: "skip", step: "timezone"})
             )
             |> json_response(422)
  end

  test "marking the step done confirms the zone the gym is on", ctx do
    %{conn: conn, owner: owner, organization: organization} = ctx

    conn
    |> put_zone(owner, %{timezone: "Europe/Madrid", source: "inferred"})
    |> json_response(200)

    conn
    |> recycle()
    |> put_bearer_token(owner)
    |> put_req_header("content-type", "application/json")
    |> patch(
      "/api/org/#{Organizations.legacy_organization_slug()}/admin/onboarding",
      Jason.encode!(%{action: "complete", step: "timezone"})
    )
    |> json_response(200)

    assert %{timezone: "Europe/Madrid", confirmed: true} =
             Organizations.timezone_status(organization.id)
  end
end
