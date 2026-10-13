defmodule MilosTraining.Organizations.AtomicOrganizationCreationTest do
  @moduledoc """
  ADR-133 / TD-094: creating an organization - vendor provisioning or an
  owner creating another gym - commits the organization, its settings, the
  owner membership or initial invitation, and the tenant defaults the caller
  seeds, or none of them.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import Ecto.Query
  import MilosTraining.TestFixtures

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations

  alias MilosTraining.Organizations.{
    Organization,
    OrganizationMembership,
    OrganizationSetting,
    RegistrationInvitation
  }

  setup do
    vendor = user_fixture()
    {:ok, _vendor} = bypass_rls(fn -> Organizations.grant_vendor(vendor.id) end)
    {:ok, platform} = Organizations.resolve_platform_context(vendor)

    owner = user_fixture()

    {:ok, home} =
      bypass_rls(fn ->
        {:ok, home} = Organizations.create_organization(%{name: "Home Gym"})

        {:ok, _membership} =
          Organizations.add_membership(%{
            organization_id: home.id,
            user_id: owner.id,
            role: :owner,
            roles: [:owner],
            status: :active,
            joined_at: DateTime.utc_now()
          })

        {:ok, home}
      end)

    %{vendor: vendor, platform: platform, owner: owner, home: home}
  end

  describe "vendor provisioning" do
    test "runs the seed in the new organization's tenant scope", ctx do
      test_pid = self()

      seed = fn scope ->
        send(test_pid, {:seeded, scope, RepoContext.current_setting("app.organization_id")})
        {:ok, :seeded}
      end

      assert {:ok, %{organization: organization}} =
               Organizations.provision_organization(ctx.platform, provision_params("seeded-gym"),
                 seed_defaults: seed
               )

      assert_received {:seeded, scope, session_organization_id}
      assert scope == %{organization_id: organization.id, user_id: ctx.vendor.id}
      assert session_organization_id == organization.id
    end

    test "a failing seed rolls the whole provisioning back", ctx do
      assert {:error, :seed_failed} =
               Organizations.provision_organization(
                 ctx.platform,
                 provision_params("doomed-gym"),
                 seed_defaults: fn _scope -> {:error, :seed_failed} end
               )

      bypass_rls(fn ->
        refute Repo.exists?(from o in Organization, where: o.slug == "doomed-gym")
        refute Repo.exists?(from s in OrganizationSetting, where: s.brand_name == "Doomed Gym")

        refute Repo.exists?(
                 from i in RegistrationInvitation,
                   join: o in Organization,
                   on: o.id == i.organization_id,
                   where: o.slug == "doomed-gym"
               )
      end)
    end
  end

  describe "an owner creating another gym" do
    test "runs the seed in the new gym's tenant scope as the owner", ctx do
      test_pid = self()

      seed = fn scope ->
        send(test_pid, {:seeded, scope, RepoContext.current_setting("app.organization_id")})
        {:ok, :seeded}
      end

      assert {:ok, organization} =
               Organizations.create_owned_organization(ctx.owner, %{name: "Second Gym"},
                 seed_defaults: seed
               )

      assert_received {:seeded, scope, session_organization_id}
      assert scope == %{organization_id: organization.id, user_id: ctx.owner.id}
      assert session_organization_id == organization.id
      assert :owner in Organizations.member_roles(organization.id, ctx.owner.id)
    end

    test "a failing seed rolls back the gym and the owner membership", ctx do
      assert {:error, :seed_failed} =
               Organizations.create_owned_organization(ctx.owner, %{name: "Doomed Owner Gym"},
                 seed_defaults: fn _scope -> {:error, :seed_failed} end
               )

      bypass_rls(fn ->
        refute Repo.exists?(from o in Organization, where: o.name == "Doomed Owner Gym")

        assert [ctx.home.id] ==
                 Repo.all(
                   from m in OrganizationMembership,
                     where: m.user_id == ^ctx.owner.id,
                     select: m.organization_id
                 )
      end)
    end

    test "an account that owns no gym is refused before anything is written", _ctx do
      outsider = user_fixture()

      assert {:error, :owner_required} =
               Organizations.create_owned_organization(outsider, %{name: "Outsider Gym"},
                 seed_defaults: fn _scope -> flunk("seed must not run") end
               )

      bypass_rls(fn ->
        refute Repo.exists?(from o in Organization, where: o.name == "Outsider Gym")
      end)
    end
  end

  defp provision_params(slug) do
    name = slug |> String.split("-") |> Enum.map_join(" ", &String.capitalize/1)
    %{"name" => name, "slug" => slug, "initial_owner_email" => "#{slug}@example.test"}
  end
end
