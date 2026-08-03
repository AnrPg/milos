defmodule MilosTrainingWeb.OrganizationAccessControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Organizations

  import MilosTraining.TestFixtures

  setup do
    owner = user_fixture()
    member = user_fixture()
    {:ok, organization} = Organizations.create_organization(%{name: "Context Gym"})

    {:ok, _owner_membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    {:ok, %{token: token}} = Organizations.issue_invitation(context, %{role: :member})

    %{owner: owner, member: member, organization: organization, token: token}
  end

  test "inspects a token without placing it in the request path", %{conn: conn, token: token} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/auth/invitations/inspect", %{invitation_token: token})

    assert %{"organization" => %{"name" => "Context Gym"}, "role" => "member"} =
             json_response(conn, 200)

    refute conn.request_path =~ token
  end

  test "an existing account redeems once and sees the membership selector entry", context do
    conn = put_bearer_token(context.conn, context.member)

    redeemed = post(conn, "/api/memberships/redeem", %{invitation_token: context.token})

    assert %{"role" => "member", "organization" => %{"slug" => slug}} =
             json_response(redeemed, 201)

    memberships =
      context.conn
      |> recycle()
      |> put_bearer_token(context.member)
      |> get("/api/memberships")

    assert [%{"organization" => %{"slug" => ^slug}, "role" => "member"}] =
             json_response(memberships, 200)
  end

  test "organization paths validate membership instead of trusting the slug", context do
    foreign =
      context.conn
      |> put_bearer_token(context.member)
      |> post("/api/org/#{context.organization.slug}/invitations", %{role: "member"})

    assert %{"code" => "organization_context_not_found"} = json_response(foreign, 404)
  end

  test "an owner can issue and revoke an organization invitation", context do
    conn = put_bearer_token(context.conn, context.owner)

    issued =
      post(conn, "/api/org/#{context.organization.slug}/invitations", %{
        role: "athlete",
        lifetime_seconds: 3_600
      })

    assert %{"token" => token, "role" => "athlete"} = json_response(issued, 201)

    {:ok, inspected} = Organizations.inspect_invitation(token)

    revoked =
      context.conn
      |> recycle()
      |> put_bearer_token(context.owner)
      |> delete("/api/org/#{context.organization.slug}/invitations/#{inspected.invitation_id}")

    assert response(revoked, 204)
    assert {:error, :invalid_invitation} = Organizations.inspect_invitation(token)
  end
end
