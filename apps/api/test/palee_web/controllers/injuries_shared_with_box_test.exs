defmodule PaleeWeb.InjuriesSharedWithBoxTest do
  @moduledoc """
  ADR-286: a member's own injury reports reach their box's staff while their
  «Να το δει το box μου» switch is on (the default); a coach reaches their own clients only (on
  the list and in every write), owners and admins everyone; `admin_only`
  reports show on the staff profile; every staff read is logged for the
  member. Runs under real RLS (ConnCase).
  """

  use PaleeWeb.ConnCase, async: false

  alias Palee.{Organizations, Repo}

  import Palee.TestFixtures

  setup do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)

    %{owner: owner, base: "/api/org/#{Organizations.legacy_organization_slug()}"}
  end

  defp person(role) do
    user = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
    user
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp as(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  defp self_report(conn, member, area, extra \\ %{}) do
    conn
    |> as(member)
    |> send_json(
      :post,
      "/api/wellbeing/injuries",
      Map.merge(%{body_area: area, severity: "mild"}, extra)
    )
    |> json_response(201)
    |> Map.fetch!("injury")
  end

  defp share(conn, member, id, shared?),
    do:
      conn
      |> as(member)
      |> send_json(:put, "/api/wellbeing/injuries/#{id}/sharing", %{shared_with_box: shared?})

  defp incidents(conn, staff, base, member),
    do:
      conn
      |> as(staff)
      |> get("#{base}/admin/users/#{member.id}/incidents")
      |> json_response(200)
      |> Map.fetch!("incidents")

  defp box_list(conn, staff, base),
    do:
      conn
      |> as(staff)
      |> get("#{base}/admin/wellbeing/injuries")
      |> json_response(200)
      |> Map.fetch!("injuries")

  test "a member's own reports reach the box unless switched off, and the member sees who read them",
       %{conn: conn, owner: owner, base: base} do
    member = person(:member)
    other_box_member = user_fixture()

    assert %{"id" => injury_id, "shared_with_box" => true} = self_report(conn, member, "knee")

    assert %{"id" => private_id, "shared_with_box" => false} =
             self_report(conn, member, "ankle", %{shared_with_box: false})

    assert [%{"id" => ^injury_id, "owned_by_member" => true, "body_area" => "knee"}] =
             incidents(conn, owner, base, member)

    listed = box_list(conn, owner, base) |> Enum.map(& &1["id"])
    assert injury_id in listed
    refute private_id in listed

    # Staff read it; only the member changes it.
    assert conn
           |> as(owner)
           |> send_json(:patch, "#{base}/admin/wellbeing/injuries/#{injury_id}/heal", %{})
           |> json_response(403)

    # Nobody else changes the switch.
    assert share(conn, other_box_member, injury_id, false) |> json_response(404)

    assert %{"entries" => entries} =
             conn |> as(member) |> get("/api/wellbeing/injuries/access-log") |> json_response(200)

    assert Enum.any?(entries, &(&1["surface"] == "profile" and &1["reader"]["id"] == owner.id))
    assert Enum.any?(entries, &(&1["surface"] == "box_list" and injury_id in &1["injury_ids"]))
    refute Enum.any?(entries, &(private_id in &1["injury_ids"]))

    # Turning it off hides it at once; on again shows it.
    assert %{"injury" => %{"shared_with_box" => false}} =
             share(conn, member, injury_id, false) |> json_response(200)

    assert incidents(conn, owner, base, member) == []

    share(conn, member, private_id, true) |> json_response(200)
    assert [%{"id" => ^private_id}] = incidents(conn, owner, base, member)
  end

  test "a box keeps seeing the reports it records itself; the switch is not theirs to flip",
       %{conn: conn, owner: owner, base: base} do
    member = person(:member)

    %{"injury" => %{"id" => id}} =
      conn
      |> as(owner)
      |> send_json(:post, "#{base}/admin/wellbeing/users/#{member.id}/injuries", %{
        body_area: "hip",
        severity: "mild"
      })
      |> json_response(201)

    assert share(conn, member, id, false) |> json_response(404)
    assert [%{"id" => ^id, "owned_by_member" => false}] = incidents(conn, owner, base, member)
  end

  test "the staff profile shows admin-only reports the member does not see",
       %{conn: conn, owner: owner, base: base} do
    member = person(:member)

    assert %{"injury" => %{"id" => id, "visibility" => "admin_only"}} =
             conn
             |> as(owner)
             |> send_json(:post, "#{base}/admin/wellbeing/users/#{member.id}/injuries", %{
               body_area: "back",
               severity: "moderate",
               visibility: "admin_only"
             })
             |> json_response(201)

    assert [%{"id" => ^id, "owned_by_member" => false}] = incidents(conn, owner, base, member)

    assert %{"injuries" => []} =
             conn |> as(member) |> get("/api/wellbeing/injuries") |> json_response(200)
  end

  test "a coach reaches their own clients only, owners everyone, the desk nobody",
       %{conn: conn, owner: owner, base: base} do
    coach = person(:coach)
    client = person(:athlete)
    other = person(:member)

    conn
    |> as(coach)
    |> send_json(:post, "#{base}/staff/coaching-relationships", %{client_user_id: client.id})
    |> json_response(201)

    report = fn staff, member ->
      conn
      |> as(staff)
      |> send_json(:post, "#{base}/admin/wellbeing/users/#{member.id}/injuries", %{
        body_area: "wrist",
        severity: "mild"
      })
    end

    assert %{"injury" => %{"id" => client_injury}} = report.(coach, client) |> json_response(201)
    assert report.(coach, other) |> json_response(403)
    assert %{"injury" => %{"id" => other_injury}} = report.(owner, other) |> json_response(201)

    ids = coach |> then(&box_list(conn, &1, base)) |> Enum.map(& &1["id"])
    assert client_injury in ids
    refute other_injury in ids

    assert conn
           |> as(coach)
           |> send_json(:patch, "#{base}/admin/wellbeing/injuries/#{other_injury}/heal", %{})
           |> json_response(403)

    assert conn
           |> as(coach)
           |> send_json(:patch, "#{base}/admin/wellbeing/injuries/#{other_injury}", %{
             note: "Looks better"
           })
           |> json_response(403)

    assert %{"injury" => %{"status" => "healed"}} =
             conn
             |> as(coach)
             |> send_json(:patch, "#{base}/admin/wellbeing/injuries/#{client_injury}/heal", %{})
             |> json_response(200)

    # Owners see everyone.
    owner_ids = owner |> then(&box_list(conn, &1, base)) |> Enum.map(& &1["id"])
    assert other_injury in owner_ids and client_injury in owner_ids

    # The front desk has no health access.
    desk = person(:front_desk)
    assert conn |> as(desk) |> get("#{base}/admin/wellbeing/injuries") |> json_response(403)
  end
end
