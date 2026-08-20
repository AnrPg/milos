defmodule MilosTrainingWeb.PlatformOrganizationControllerTest do
  use MilosTrainingWeb.ConnCase, async: false
  import Swoosh.TestAssertions

  alias MilosTraining.{Identity, Organizations}

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
    {:ok, _vendor} = Organizations.grant_vendor(platform_user.id)

    %{platform_user: platform_user, ordinary_user: ordinary_user}
  end

  test "only a vendor can access provisioning", context do
    conn =
      context.conn
      |> put_bearer_token(context.ordinary_user)
      |> get("/api/platform/organizations")

    assert %{"code" => "vendor_required"} = json_response(conn, 403)
  end

  test "provisions organization, settings, audit event, and a copy-once admin token", context do
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

    refute Repo.exists?(
             from membership in OrganizationMembership,
               where:
                 membership.organization_id == ^organization_id and
                   membership.user_id == ^context.platform_user.id
           )

    assert response["initial_owner_invitation"]["role"] == "admin"

    assert {:ok, %{organization: %{id: ^organization_id}, role: :admin}} =
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

  test "lists a newly-provisioned organization as pending until its admin invitation is redeemed",
       context do
    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> post("/api/platform/organizations", %{
        name: "Pending Gym",
        timezone: "Europe/Athens",
        default_locale: "el",
        initial_owner_email: "owner@example.test"
      })

    %{
      "organization" => %{"id" => organization_id},
      "initial_owner_invitation" => %{"token" => token}
    } =
      json_response(conn, 201)

    pending_index =
      context.conn
      |> recycle()
      |> put_bearer_token(context.platform_user)
      |> get("/api/platform/organizations")

    entry =
      json_response(pending_index, 200)["organizations"]
      |> Enum.find(&(&1["organization"]["id"] == organization_id))

    assert entry["pending_registration"] == true

    new_admin = user_fixture(%{nickname: "pending_gym_admin", email: "owner@example.test"})

    assert {:ok, %{membership: %{role: :admin}}} =
             Organizations.redeem_invitation(token, new_admin.id)

    redeemed_index =
      context.conn
      |> recycle()
      |> put_bearer_token(context.platform_user)
      |> get("/api/platform/organizations")

    entry =
      json_response(redeemed_index, 200)["organizations"]
      |> Enum.find(&(&1["organization"]["id"] == organization_id))

    assert entry["pending_registration"] == false
  end

  test "the provisioned initial admin invitation registers a client through the setup link endpoint",
       context do
    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> post("/api/platform/organizations", %{
        name: "Client Setup Gym",
        timezone: "Europe/Athens",
        default_locale: "el",
        initial_owner_email: "client@example.test"
      })

    %{
      "organization" => %{"id" => organization_id},
      "initial_owner_invitation" => %{"token" => token, "role" => "admin"}
    } =
      json_response(conn, 201)

    register_conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/auth/register-admin",
        Jason.encode!(%{
          nickname: "client_admin",
          password: "S3cur3P@ss!42",
          invitation_token: token,
          email: "client@example.test"
        })
      )

    assert %{"access_token" => _} = json_response(register_conn, 201)
    account = Identity.find_by_nickname("client_admin")
    assert account.role == :admin

    assert [
             %{
               membership: %{role: :admin, status: :active},
               organization: %{id: ^organization_id}
             }
           ] = Organizations.list_memberships(account.id)
  end

  test "requires an initial admin email to provision an organization", context do
    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> post("/api/platform/organizations", %{
        name: "No Email Gym",
        timezone: "Europe/Athens",
        default_locale: "el"
      })

    assert %{"code" => "owner_email_required"} = json_response(conn, 422)

    refute Repo.exists?(
             from organization in Organization, where: organization.name == "No Email Gym"
           )
  end

  test "emails the initial owner their setup link and audits the send", context do
    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> post("/api/platform/organizations", %{
        name: "Emailed Gym",
        timezone: "Europe/Athens",
        default_locale: "el",
        initial_owner_email: "owner@example.test"
      })

    %{
      "organization" => %{"id" => organization_id},
      "initial_owner_invitation" => %{"token" => token}
    } =
      json_response(conn, 201)

    email_conn =
      context.conn
      |> recycle()
      |> put_bearer_token(context.platform_user)
      |> post("/api/platform/organizations/#{organization_id}/invitations/email", %{
        email: "Owner@Example.test",
        token: token
      })

    assert response(email_conn, 204) == ""

    assert_email_sent(fn email ->
      assert email.to == [{"", "owner@example.test"}]
      assert email.subject =~ "Emailed Gym"
      assert email.text_body =~ token
      assert email.html_body =~ token
    end)

    assert Repo.exists?(
             from event in OrganizationProvisioningEvent,
               where:
                 event.organization_id == ^organization_id and
                   event.event == "organization_invitation_emailed"
           )
  end

  test "rejects sending an invitation email without an email or token", context do
    {:ok, organization} = Organizations.create_organization(%{name: "Missing Fields Gym"})

    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> post("/api/platform/organizations/#{organization.id}/invitations/email", %{token: "abc"})

    assert %{"code" => "invalid_email"} = json_response(conn, 422)
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

  test "permanent delete purges tenant-only accounts so invited client emails can register again",
       context do
    {:ok, organization} = Organizations.create_organization(%{name: "Reusable Email Gym"})

    stale_client =
      admin_fixture(%{
        nickname: "reusable_email_admin",
        email: "reusable@example.test"
      })

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: stale_client.id,
        role: :admin,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> delete("/api/platform/organizations/#{organization.id}")

    assert response(conn, 204) == ""
    refute Repo.get(Organization, organization.id)
    refute Identity.find_by_id(stale_client.id)

    assert {:ok, fresh_client} =
             Identity.register(%{
               nickname: "fresh_reusable_admin",
               email: "reusable@example.test",
               password: "S3cur3P@ss!42",
               role: :member
             })

    assert fresh_client.email == "reusable@example.test"
  end

  test "permanent delete can purge a tenant-only admin without treating it as global last admin",
       context do
    {:ok, organization} = Organizations.create_organization(%{name: "Last Tenant Admin Gym"})

    tenant_admin =
      admin_fixture(%{
        nickname: "last_tenant_admin",
        email: "last-tenant-admin@example.test"
      })

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: tenant_admin.id,
        role: :admin,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> delete("/api/platform/organizations/#{organization.id}")

    assert response(conn, 204) == ""
    refute Repo.get(Organization, organization.id)
    refute Identity.find_by_id(tenant_admin.id)
  end

  test "permanent delete keeps SaaS owner and accounts that still belong to another organization",
       context do
    {:ok, doomed_organization} = Organizations.create_organization(%{name: "Doomed Gym"})
    {:ok, survivor_organization} = Organizations.create_organization(%{name: "Survivor Gym"})
    shared_user = admin_fixture(%{nickname: "shared_tenant_admin"})

    for organization <- [doomed_organization, survivor_organization] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: shared_user.id,
          role: :admin,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, _owner_membership} =
      Organizations.add_membership(%{
        organization_id: doomed_organization.id,
        user_id: context.platform_user.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> delete("/api/platform/organizations/#{doomed_organization.id}")

    assert response(conn, 204) == ""
    assert Identity.find_by_id(context.platform_user.id)
    assert Identity.find_by_id(shared_user.id)

    assert Repo.exists?(
             from membership in OrganizationMembership,
               where:
                 membership.organization_id == ^survivor_organization.id and
                   membership.user_id == ^shared_user.id
           )
  end

  test "permanently deletes an organization that has real tenant data (previously RESTRICT-only tables)",
       context do
    alias MilosTraining.Gamification.GamificationSetting

    {:ok, organization} = Organizations.create_organization(%{name: "Used Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: context.platform_user.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, _gamification_settings} =
      %GamificationSetting{}
      |> GamificationSetting.changeset(%{
        organization_id: organization.id,
        weekly_workout_target: 3,
        leaderboard_enabled: true,
        theme_slug: "ember"
      })
      |> Repo.insert()

    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> delete("/api/platform/organizations/#{organization.id}")

    assert response(conn, 204) == ""
    refute Repo.get(Organization, organization.id)

    refute Repo.exists?(
             from settings in GamificationSetting,
               where: settings.organization_id == ^organization.id
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

  test "renames an organization without changing its slug or canonical path", context do
    {:ok, organization} = Organizations.create_organization(%{name: "Old Name Gym"})
    original_slug = organization.slug

    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> patch("/api/platform/organizations/#{organization.id}/name", %{name: "New Name Gym"})

    assert %{"organization" => %{"name" => "New Name Gym", "slug" => ^original_slug}} =
             json_response(conn, 200)

    assert %{name: "New Name Gym", slug: ^original_slug} =
             Repo.get!(Organization, organization.id)

    assert Repo.exists?(
             from event in OrganizationProvisioningEvent,
               where:
                 event.organization_id == ^organization.id and
                   event.event == "organization_renamed"
           )
  end

  test "rejects a name shorter than the minimum length", context do
    {:ok, organization} = Organizations.create_organization(%{name: "Short Name Gym"})

    conn =
      context.conn
      |> put_bearer_token(context.platform_user)
      |> patch("/api/platform/organizations/#{organization.id}/name", %{name: "A"})

    assert json_response(conn, 422)
    assert Repo.get!(Organization, organization.id).name == "Short Name Gym"
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
