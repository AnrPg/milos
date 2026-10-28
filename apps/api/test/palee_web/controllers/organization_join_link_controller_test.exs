defmodule PaleeWeb.OrganizationJoinLinkControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Identity, Organizations}

  import Palee.TestFixtures

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
    assert %{
             "member" => %{"enabled" => false},
             "athlete" => %{"enabled" => false, "key" => nil}
           } =
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
               Jason.encode!(%{role: "admin", enabled: true})
             )
             |> json_response(422)
  end

  defp visitor do
    {:ok, visitor} =
      Identity.register(%{
        nickname: "join_visitor#{System.unique_integer([:positive])}",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "visitor#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    visitor
  end

  defp join(context, user, path) do
    context.conn |> recycle() |> put_bearer_token(user) |> post(path)
  end

  test "the athlete link joins with the athlete role, idempotently", context do
    assert %{"athlete" => %{"enabled" => true, "key" => key}, "member" => %{"enabled" => false}} =
             enable_link(context, %{role: "athlete", enabled: true})

    assert is_binary(key)
    slug = context.organization.slug

    assert %{"organization" => %{"name" => "Join Gym"}, "role" => "athlete"} =
             context.conn
             |> get("/api/auth/join/#{slug}/athlete/#{key}")
             |> json_response(200)

    visitor = visitor()

    joined =
      context
      |> join(visitor, "/api/memberships/join/#{slug}/athlete/#{key}")
      |> json_response(201)

    assert joined["role"] == "athlete"
    assert joined["organization"]["slug"] == slug
    # The account role changed, so earlier access tokens are stale; the web
    # client refreshes its session after joining.
    visitor = Identity.find_by_id(visitor.id)
    assert visitor.role == :athlete

    assert %{"role" => "athlete"} =
             context
             |> join(visitor, "/api/memberships/join/#{slug}/athlete/#{key}")
             |> json_response(200)
  end

  test "both links work at once, each with its own role", context do
    enable_link(context, %{role: "member", enabled: true})
    %{"athlete" => %{"key" => key}} = enable_link(context, %{role: "athlete", enabled: true})
    slug = context.organization.slug

    assert %{"role" => "member"} =
             context.conn |> get("/api/auth/join/#{slug}") |> json_response(200)

    assert %{"role" => "member"} =
             context |> join(visitor(), "/api/memberships/join/#{slug}") |> json_response(201)

    assert %{"role" => "athlete"} =
             context
             |> join(visitor(), "/api/memberships/join/#{slug}/athlete/#{key}")
             |> json_response(201)
  end

  test "the member link never grants the athlete role, and a wrong key is unavailable", context do
    enable_link(context, %{role: "athlete", enabled: true})
    slug = context.organization.slug

    # Only the athlete link is on: the box address alone does not let anyone in.
    assert %{"code" => "join_link_unavailable"} =
             context.conn |> get("/api/auth/join/#{slug}") |> json_response(404)

    assert %{"code" => "join_link_unavailable"} =
             context |> join(visitor(), "/api/memberships/join/#{slug}") |> json_response(404)

    assert %{"code" => "join_link_unavailable"} =
             context.conn |> get("/api/auth/join/#{slug}/athlete/guess") |> json_response(404)

    assert %{"code" => "join_link_unavailable"} =
             context
             |> join(visitor(), "/api/memberships/join/#{slug}/athlete/guess")
             |> json_response(404)
  end

  test "a new athlete key retires the old address", context do
    %{"athlete" => %{"key" => old}} = enable_link(context, %{role: "athlete", enabled: true})

    %{"athlete" => %{"enabled" => true, "key" => new}} =
      enable_link(context, %{role: "athlete", rotate_key: true})

    refute old == new
    slug = context.organization.slug

    context.conn |> get("/api/auth/join/#{slug}/athlete/#{old}") |> json_response(404)
    context.conn |> get("/api/auth/join/#{slug}/athlete/#{new}") |> json_response(200)
  end

  test "joining never changes an existing staff membership", context do
    enable_link(context, %{role: "member", enabled: true})

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
