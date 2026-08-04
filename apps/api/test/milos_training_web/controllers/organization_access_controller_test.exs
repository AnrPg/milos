defmodule MilosTrainingWeb.OrganizationAccessControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Organizations, Repo}
  alias MilosTraining.Organizations.OrganizationSetting

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

    OrganizationSetting
    |> Repo.get_by!(organization_id: context.organization.id)
    |> OrganizationSetting.changeset(%{
      timezone: "Europe/Athens",
      default_locale: "el",
      invitation_lifetime_seconds: 604_800,
      brand_name: "Context Gym App",
      brand_logo_url: "https://cdn.example.test/context-gym.png",
      brand_primary_color: "#336699",
      settings: %{}
    })
    |> Repo.update!()

    memberships =
      context.conn
      |> recycle()
      |> put_bearer_token(context.member)
      |> get("/api/memberships")

    assert Enum.any?(json_response(memberships, 200), fn entry ->
             entry["organization"]["slug"] == slug and entry["role"] == "member" and
               entry["settings"]["brand_name"] == "Context Gym App" and
               entry["settings"]["brand_logo_url"] == "https://cdn.example.test/context-gym.png" and
               entry["settings"]["brand_primary_color"] == "#336699"
           end)
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

  test "tenant review endpoints require membership and scope a member's review", context do
    member_conn =
      context.conn
      |> put_bearer_token(context.member)

    redeemed = post(member_conn, "/api/memberships/redeem", %{invitation_token: context.token})
    assert %{"role" => "member"} = json_response(redeemed, 201)

    created =
      context.conn
      |> recycle()
      |> put_bearer_token(context.member)
      |> post("/api/org/#{context.organization.slug}/me/reviews", %{
        target_type: "general",
        rating: 5,
        sentiment: "positive",
        body: "The class plan was clear.",
        answers: [
          %{
            question_key: "difficulty",
            question_text: "How did the difficulty fit?",
            answer_text: "Right level",
            rating_value: 5
          }
        ]
      })

    assert %{"review" => %{"rating" => 5} = review} = json_response(created, 201)

    listed =
      context.conn
      |> recycle()
      |> put_bearer_token(context.member)
      |> get("/api/org/#{context.organization.slug}/me/reviews")

    assert [review_id] = Enum.map(json_response(listed, 200)["reviews"], & &1["id"])
    assert review_id == review["id"]

    outsider = user_fixture()

    rejected =
      context.conn
      |> recycle()
      |> put_bearer_token(outsider)
      |> get("/api/org/#{context.organization.slug}/me/reviews")

    assert %{"code" => "organization_context_not_found"} = json_response(rejected, 404)
  end

  test "an organization admin cannot open another organization's athlete coaching drill-down",
       context do
    foreign_owner = user_fixture()
    foreign_athlete = user_fixture(%{role: :athlete})

    {:ok, foreign_organization} =
      Organizations.create_organization(%{name: "Foreign Coaching Gym"})

    for {user, role} <- [{foreign_owner, :owner}, {foreign_athlete, :athlete}] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: foreign_organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    conn =
      context.conn
      |> put_bearer_token(context.owner)
      |> get(
        "/api/org/#{context.organization.slug}/admin/athletes/#{foreign_athlete.id}/drill-down"
      )

    assert %{"error" => "Not found"} = json_response(conn, 404)
  end
end
