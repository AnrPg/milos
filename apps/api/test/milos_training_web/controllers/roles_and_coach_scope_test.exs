defmodule MilosTrainingWeb.RolesAndCoachScopeTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Notifications, Organizations, Repo}

  import MilosTraining.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    coach = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(coach, :coach)

    %{
      conn: conn,
      owner: owner,
      owner_conn: put_bearer_token(conn, owner),
      coach: coach,
      coach_conn: put_bearer_token(conn, coach),
      base: "/api/org/#{Organizations.legacy_organization_slug()}"
    }
  end

  defp client(role) do
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

  test "a coach sees only their own clients until made head coach", %{
    owner: owner,
    owner_conn: owner_conn,
    coach: coach,
    coach_conn: coach_conn,
    base: base
  } do
    mine = client(:athlete)
    theirs = client(:member)

    # A coach may take an athlete, never a member; owners hear about it.
    assert %{"code" => "only_athletes_self_assigned"} =
             coach_conn
             |> send_json(:post, "#{base}/staff/coaching-relationships", %{
               client_user_id: theirs.id
             })
             |> json_response(422)

    assert %{"relationship" => %{"origin" => "self_assigned"}} =
             coach_conn
             |> send_json(:post, "#{base}/staff/coaching-relationships", %{
               client_user_id: mine.id
             })
             |> json_response(201)

    assert Enum.any?(
             Notifications.list_for_user(owner.id),
             &(&1.type == "coach_client_assigned")
           )

    listed =
      coach_conn
      |> recycle()
      |> get("#{base}/admin/users")
      |> json_response(200)
      |> Map.fetch!("users")
      |> Enum.map(& &1["id"])

    assert listed == [mine.id]

    assert coach_conn
           |> recycle()
           |> get("#{base}/admin/users/#{theirs.id}")
           |> json_response(403)

    assert coach_conn |> recycle() |> get("#{base}/admin/users/#{mine.id}") |> json_response(200)

    # Money stays out of reach; the status read model is allowed.
    assert coach_conn |> recycle() |> get("#{base}/admin/finance/members") |> json_response(403)

    assert %{"membership_status" => %{"status" => _}} =
             coach_conn
             |> recycle()
             |> get("#{base}/admin/users/#{mine.id}/membership-status")
             |> json_response(200)

    assert %{"membership" => %{"coach_scope" => "all"}} =
             owner_conn
             |> send_json(:patch, "#{base}/admin/users/#{coach.id}/coach-scope", %{
               coach_scope: "all"
             })
             |> json_response(200)

    assert coach_conn
           |> recycle()
           |> get("#{base}/admin/users/#{theirs.id}")
           |> json_response(200)
  end

  test "owners set role sets; a gym keeps an owner; invitations add roles", %{
    owner: owner,
    owner_conn: owner_conn,
    coach: coach,
    coach_conn: coach_conn,
    base: base
  } do
    assert %{"membership" => %{"roles" => ["coach", "member"], "role" => "coach"}} =
             owner_conn
             |> send_json(:put, "#{base}/admin/users/#{coach.id}/roles", %{
               roles: ["member", "coach"]
             })
             |> json_response(200)

    assert coach_conn |> recycle() |> get("#{base}/admin/finance/summary") |> json_response(403)

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)

    assert {:error, :cannot_change_own_membership} =
             Organizations.set_membership_roles(owner_context, owner.id, ["member"])

    desk = client(:member)
    {:ok, %{token: token}} = Organizations.issue_invitation(owner_context, %{role: :front_desk})
    {:ok, %{membership: membership}} = Organizations.redeem_invitation(token, desk.id)
    assert membership.roles == [:front_desk, :member]
  end
end
