defmodule MilosTrainingWeb.PlatformOrganizationControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Organizations

  alias MilosTraining.Organizations.{
    Organization,
    OrganizationMembership,
    OrganizationProvisioningEvent,
    RegistrationInvitation
  }

  alias MilosTraining.Repo

  import Ecto.Query
  import MilosTraining.TestFixtures

  setup do
    platform_user = user_fixture(%{nickname: "platform_operator"})
    ordinary_user = user_fixture(%{nickname: "tenant_operator"})
    {:ok, _owner} = Organizations.grant_platform_owner(platform_user.id)

    %{platform_user: platform_user, ordinary_user: ordinary_user}
  end

  test "only a platform owner can access provisioning", context do
    conn =
      context.conn
      |> put_bearer_token(context.ordinary_user)
      |> get("/api/platform/organizations")

    assert %{"code" => "platform_owner_required"} = json_response(conn, 403)
  end

  test "provisions organization, settings, audit event, and a copy-once owner token", context do
    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> post("/api/platform/organizations", %{
        name: "North Harbor Strength",
        slug: "north-harbor-strength",
        timezone: "Europe/Athens",
        default_locale: "el",
        invitation_lifetime_seconds: 3_600,
        initial_owner_email: "owner@example.test",
        brand_name: "North Harbor",
        brand_primary_color: "#1F6F5F"
      })

    response = json_response(conn, 201)
    organization_id = response["organization"]["id"]
    token = response["initial_owner_invitation"]["token"]

    assert response["canonical_path"] == "/org/north-harbor-strength"
    assert response["settings"]["timezone"] == "Europe/Athens"
    assert response["settings"]["brand_name"] == "North Harbor"
    assert is_binary(token)

    assert Repo.exists?(
             from membership in OrganizationMembership,
               where:
                 membership.organization_id == ^organization_id and
                   membership.user_id == ^context.platform_user.id and
                   membership.role == :owner and
                   membership.status == :active
           )

    assert {:ok, %{organization: %{id: ^organization_id}, role: :owner}} =
             Organizations.inspect_invitation(token)

    invitation = Repo.one!(from invitation in RegistrationInvitation, limit: 1)
    refute invitation.token_digest == token
    refute inspect(invitation) =~ token

    assert Repo.exists?(
             from event in OrganizationProvisioningEvent,
               where:
                 event.organization_id == ^organization_id and
                   event.event == "organization_provisioned"
           )
  end

  test "permanently deletes an organization created by mistake", context do
    {:ok, organization} = Organizations.create_organization(%{name: "Mistake Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: context.platform_user.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> delete("/api/platform/organizations/#{organization.id}")

    assert response(conn, 204) == ""
    refute Repo.get(Organization, organization.id)

    refute Repo.exists?(
             from membership in OrganizationMembership,
               where: membership.organization_id == ^organization.id
           )
  end

  test "platform owner manages tenant invitations and membership roles", context do
    {:ok, organization} = Organizations.create_organization(%{name: "Access Gym"})
    member = user_fixture(%{nickname: "access_member", role: :member})

    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: member.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    conn = put_bearer_token(context.conn, context.platform_user)

    access = get(conn, "/api/platform/organizations/#{organization.id}/access")

    assert %{"memberships" => memberships} = json_response(access, 200)

    assert Enum.any?(memberships, fn entry ->
             entry["id"] == membership.id and entry["role"] == "member" and
               entry["user"]["nickname"] == "access_member"
           end)

    invited =
      context.conn
      |> recycle()
      |> put_bearer_token(context.platform_user)
      |> post("/api/platform/organizations/#{organization.id}/invitations", %{
        role: "coach",
        intended_email: "coach@example.test",
        lifetime_seconds: 3_600
      })

    assert %{"invitation" => %{"token" => token, "role" => "coach"}} =
             json_response(invited, 201)

    assert {:ok, %{organization: %{id: organization_id}, role: :coach}} =
             Organizations.inspect_invitation(token)

    assert organization_id == organization.id

    updated =
      context.conn
      |> recycle()
      |> put_bearer_token(context.platform_user)
      |> patch(
        "/api/platform/organizations/#{organization.id}/memberships/#{membership.id}/role",
        %{
          role: "athlete"
        }
      )

    assert %{"membership" => %{"id" => membership_id, "role" => "athlete"}} =
             json_response(updated, 200)

    assert membership_id == membership.id
    assert Repo.get!(OrganizationMembership, membership.id).role == :athlete
  end

  test "lifecycle and settings changes are audited and suspended tenants cannot resolve",
       context do
    {:ok, organization} = Organizations.create_organization(%{name: "Lifecycle Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: context.ordinary_user.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    base_conn = put_bearer_token(context.conn, context.platform_user)

    settings_conn =
      patch(base_conn, "/api/platform/organizations/#{organization.id}/settings", %{
        timezone: "Europe/London",
        default_locale: "en",
        invitation_lifetime_seconds: 7_200,
        brand_primary_color: "#336699",
        ignored_browser_field: "not persisted"
      })

    assert %{"settings" => %{"timezone" => "Europe/London"}} =
             json_response(settings_conn, 200)

    lifecycle_conn =
      context.conn
      |> recycle()
      |> put_bearer_token(context.platform_user)
      |> patch("/api/platform/organizations/#{organization.id}/lifecycle", %{status: "suspended"})

    assert %{"organization" => %{"status" => "suspended"}} =
             json_response(lifecycle_conn, 200)

    assert {:error, :inactive_organization} =
             Organizations.resolve_tenant_context(context.ordinary_user, organization.slug)

    events =
      Repo.all(
        from event in OrganizationProvisioningEvent,
          where: event.organization_id == ^organization.id,
          select: event.event
      )

    assert "organization_settings_updated" in events
    assert "organization_suspended" in events
  end

  test "archiving an organization soft-deletes tenant access and records lifecycle audit",
       context do
    {:ok, organization} = Organizations.create_organization(%{name: "Archive Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: context.ordinary_user.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> patch("/api/platform/organizations/#{organization.id}/lifecycle", %{status: "archived"})

    assert %{"organization" => %{"status" => "archived"}} = json_response(conn, 200)

    assert {:error, :inactive_organization} =
             Organizations.resolve_tenant_context(context.ordinary_user, organization.slug)

    assert Repo.exists?(
             from event in OrganizationProvisioningEvent,
               where:
                 event.organization_id == ^organization.id and
                   event.event == "organization_archived"
           )
  end
end
