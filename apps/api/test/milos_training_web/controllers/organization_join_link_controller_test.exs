defmodule MilosTrainingWeb.OrganizationJoinLinkControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Identity, Organizations}

  import MilosTraining.TestFixtures

  setup do
    owner = user_fixture()
    {:ok, organization} = Organizations.create_organization(%{name: "Join Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    %{owner: owner, organization: organization}
  end

  defp admin_conn(context), do: context.conn |> recycle() |> put_bearer_token(context.owner)

  defp enable_link(context, params) do
    context
    |> admin_conn()
    |> put_req_header("content-type", "application/json")
    |> put("/api/org/#{context.organization.slug}/join-link", Jason.encode!(params))
    |> json_response(200)
  end

  test "pending invitations are listed for admins without exposing tokens", context do
    conn = admin_conn(context)

    conn
    |> post("/api/org/#{context.organization.slug}/invitations", %{
      role: "athlete",
      intended_email: "a@b.test"
    })
    |> json_response(201)

    [invitation] =
      context
      |> admin_conn()
      |> get("/api/org/#{context.organization.slug}/invitations")
      |> json_response(200)

    assert invitation["role"] == "athlete"
    assert invitation["email_bound"] == true
    refute Map.has_key?(invitation, "token")

    context
    |> admin_conn()
    |> delete("/api/org/#{context.organization.slug}/invitations/#{invitation["id"]}")
    |> response(204)

    assert [] ==
             context
             |> admin_conn()
             |> get("/api/org/#{context.organization.slug}/invitations")
             |> json_response(200)
  end

  test "the join link is disabled by default and hidden from the public", context do
    assert %{"enabled" => false, "role" => "member"} =
             context
             |> admin_conn()
             |> get("/api/org/#{context.organization.slug}/join-link")
             |> json_response(200)

    assert %{"code" => "join_link_unavailable"} =
             context.conn
             |> get("/api/auth/join/#{context.organization.slug}")
             |> json_response(404)

    assert %{"code" => "join_link_unavailable"} =
             context.conn
             |> get("/api/auth/join/no-such-gym")
             |> json_response(404)
  end

  test "admins cannot open the link to staff roles", context do
    assert %{"code" => "invalid_join_link"} =
             context
             |> admin_conn()
             |> put_req_header("content-type", "application/json")
             |> put(
               "/api/org/#{context.organization.slug}/join-link",
               Jason.encode!(%{role: "admin"})
             )
             |> json_response(422)
  end

  test "a client account joins with the configured role, idempotently", context do
    assert %{"enabled" => true, "role" => "athlete"} =
             enable_link(context, %{enabled: true, role: "athlete"})

    assert %{"organization" => %{"name" => "Join Gym"}, "role" => "athlete"} =
             context.conn
             |> get("/api/auth/join/#{context.organization.slug}")
             |> json_response(200)

    {:ok, visitor} =
      Identity.register(%{
        nickname: "join_visitor",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "visitor#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    joined =
      context.conn
      |> recycle()
      |> put_bearer_token(visitor)
      |> post("/api/memberships/join/#{context.organization.slug}")
      |> json_response(201)

    assert joined["role"] == "athlete"
    assert joined["organization"]["slug"] == context.organization.slug
    # The account role changed, so earlier access tokens are stale; the web
    # client refreshes its session after joining.
    visitor = Identity.find_by_id(visitor.id)
    assert visitor.role == :athlete

    assert %{"role" => "athlete"} =
             context.conn
             |> recycle()
             |> put_bearer_token(visitor)
             |> post("/api/memberships/join/#{context.organization.slug}")
             |> json_response(200)
  end

  test "joining never changes an existing staff membership", context do
    enable_link(context, %{enabled: true})

    assert %{"role" => "owner"} =
             context
             |> admin_conn()
             |> post("/api/memberships/join/#{context.organization.slug}")
             |> json_response(200)
  end

  test "a disabled link cannot be used to join", context do
    visitor = user_fixture()

    assert %{"code" => "join_link_unavailable"} =
             context.conn
             |> put_bearer_token(visitor)
             |> post("/api/memberships/join/#{context.organization.slug}")
             |> json_response(404)
  end

  test "members cannot manage the join link", context do
    member = user_fixture()

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: context.organization.id,
        user_id: member.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    context.conn
    |> put_bearer_token(member)
    |> get("/api/org/#{context.organization.slug}/join-link")
    |> json_response(403)
  end
end
