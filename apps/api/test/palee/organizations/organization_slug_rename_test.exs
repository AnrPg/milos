defmodule Palee.Organizations.OrganizationSlugRenameTest do
  @moduledoc "ADR-122: slug rename, retired-slug aliases and alias reservation."
  use Palee.DataCase, async: false

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Application.{
    GetOrganizationSlugRenameImpact,
    RenameOrganizationSlug,
    ResolveOrganizationSlugAlias
  }

  alias Palee.Organizations

  alias Palee.Organizations.{
    Organization,
    OrganizationProvisioningEvent,
    OrganizationSlugAlias,
    TenantContext
  }

  alias Palee.Repo

  setup do
    vendor = user_fixture()
    member = user_fixture()
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
    {:ok, platform} = Organizations.resolve_platform_context(vendor)

    {:ok, organization} =
      Organizations.create_organization(%{name: "Harbor Gym", slug: "harbor-gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: member.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    %{vendor: vendor, member: member, platform: platform, organization: organization}
  end

  defp rename(ctx, slug, confirmation),
    do:
      RenameOrganizationSlug.call(ctx.platform, ctx.organization.id, %{
        "slug" => slug,
        "confirmation" => confirmation
      })

  test "renames the slug, keeps the old slug as an alias and audits it in one transaction",
       ctx do
    assert {:ok, result} = rename(ctx, "north-harbor", "harbor-gym")

    assert result.organization.slug == "north-harbor"
    assert result.organization.name == "Harbor Gym"
    assert result.previous_slug == "harbor-gym"
    assert [%OrganizationSlugAlias{slug: "harbor-gym"}] = result.aliases

    assert Repo.get!(Organization, ctx.organization.id).slug == "north-harbor"

    assert %OrganizationProvisioningEvent{metadata: metadata} =
             Repo.one!(
               from event in OrganizationProvisioningEvent,
                 where:
                   event.organization_id == ^ctx.organization.id and
                     event.event == "organization_slug_renamed"
             )

    assert metadata["previous_slug"] == "harbor-gym"
    assert metadata["slug"] == "north-harbor"
  end

  test "a member resolves the tenant context through the retired slug", ctx do
    assert {:ok, _result} = rename(ctx, "north-harbor", "harbor-gym")

    assert {:ok, %TenantContext{organization: %{slug: "north-harbor"}} = context} =
             Organizations.resolve_tenant_context(ctx.member, "harbor-gym", %{transport: :test})

    assert context.organization_id == ctx.organization.id
  end

  test "a non-member still cannot resolve the organization through the retired slug", ctx do
    assert {:ok, _result} = rename(ctx, "north-harbor", "harbor-gym")
    outsider = user_fixture()

    assert {:error, _reason} =
             Organizations.resolve_tenant_context(outsider, "harbor-gym", %{transport: :test})
  end

  test "the public alias lookup maps only retired slugs", ctx do
    assert {:ok, _result} = rename(ctx, "north-harbor", "harbor-gym")

    assert ResolveOrganizationSlugAlias.call("harbor-gym") == {:ok, "north-harbor"}
    assert ResolveOrganizationSlugAlias.call("north-harbor") == {:error, :not_found}
    assert ResolveOrganizationSlugAlias.call("never-existed") == {:error, :not_found}
    assert ResolveOrganizationSlugAlias.call("../etc") == {:error, :not_found}
  end

  test "a retired slug cannot be claimed by another organization", ctx do
    assert {:ok, _result} = rename(ctx, "north-harbor", "harbor-gym")

    {:ok, other} = Organizations.create_organization(%{name: "Other Gym", slug: "other-gym"})

    assert {:error, :slug_taken} =
             RenameOrganizationSlug.call(ctx.platform, other.id, %{
               "slug" => "harbor-gym",
               "confirmation" => "other-gym"
             })

    assert {:error, :slug_taken} =
             RenameOrganizationSlug.call(ctx.platform, other.id, %{
               "slug" => "north-harbor",
               "confirmation" => "other-gym"
             })

    # Provisioning a brand-new organization cannot take it either.
    assert {:error, %Ecto.Changeset{} = changeset} =
             Organizations.provision_organization(ctx.platform, %{
               "name" => "Squatter",
               "slug" => "harbor-gym",
               "initial_owner_email" => "squatter@example.test"
             })

    assert %{slug: ["has already been taken"]} = errors_on(changeset)

    assert {:error, %Ecto.Changeset{}} =
             Organizations.create_organization(%{name: "Squatter", slug: "harbor-gym"})
  end

  test "an organization can rename back to one of its own retired slugs", ctx do
    assert {:ok, _result} = rename(ctx, "north-harbor", "harbor-gym")
    assert {:ok, result} = rename(ctx, "harbor-gym", "north-harbor")

    assert result.organization.slug == "harbor-gym"
    assert Enum.map(result.aliases, & &1.slug) == ["north-harbor"]

    assert ResolveOrganizationSlugAlias.call("north-harbor") == {:ok, "harbor-gym"}
    assert ResolveOrganizationSlugAlias.call("harbor-gym") == {:error, :not_found}
  end

  test "requires the current slug retyped and a valid, changed slug", ctx do
    assert {:error, :slug_confirmation_mismatch} = rename(ctx, "north-harbor", "north-harbor")
    assert {:error, :slug_confirmation_mismatch} = rename(ctx, "north-harbor", nil)
    assert {:error, :invalid_slug} = rename(ctx, "North Harbor!", "harbor-gym")
    assert {:error, :slug_unchanged} = rename(ctx, "harbor-gym", "harbor-gym")

    assert Repo.get!(Organization, ctx.organization.id).slug == "harbor-gym"
    refute Repo.exists?(OrganizationSlugAlias)
  end

  test "rejects another organization's canonical slug", ctx do
    {:ok, _other} = Organizations.create_organization(%{name: "Other Gym", slug: "other-gym"})

    assert {:error, :slug_taken} = rename(ctx, "other-gym", "harbor-gym")
  end

  test "an open purge blocks the rename so the purge confirmation slug stays valid", ctx do
    assert {:ok, _purge} =
             Organizations.request_organization_purge(ctx.platform, ctx.organization.id)

    assert {:error, :slug_rename_blocked_by_purge} = rename(ctx, "north-harbor", "harbor-gym")
  end

  test "only vendors can rename slugs or read the impact", ctx do
    assert {:error, :vendor_required} =
             RenameOrganizationSlug.call(nil, ctx.organization.id, %{
               "slug" => "north-harbor",
               "confirmation" => "harbor-gym"
             })

    assert {:error, :vendor_required} =
             GetOrganizationSlugRenameImpact.call(nil, ctx.organization.id)
  end

  test "summarizes active members, pending invitations and retired slugs", ctx do
    {:ok, _invitation} =
      Organizations.issue_platform_invitation(ctx.platform, ctx.organization.id, %{
        "role" => "member"
      })

    assert {:ok, impact} = GetOrganizationSlugRenameImpact.call(ctx.platform, ctx.organization.id)
    assert impact.active_member_count == 1
    assert impact.pending_invitation_count == 1
    assert impact.aliases == []
    refute impact.purge_open

    assert {:ok, _result} = rename(ctx, "north-harbor", "harbor-gym")
    assert {:ok, impact} = GetOrganizationSlugRenameImpact.call(ctx.platform, ctx.organization.id)
    assert Enum.map(impact.aliases, & &1.slug) == ["harbor-gym"]
  end

  test "retired slugs are removed with the organization", ctx do
    assert {:ok, _result} = rename(ctx, "north-harbor", "harbor-gym")
    assert {:ok, _deleted} = Organizations.delete_organization(ctx.platform, ctx.organization.id)

    refute Repo.exists?(OrganizationSlugAlias)
    assert {:ok, _new} = Organizations.create_organization(%{name: "Fresh", slug: "harbor-gym"})
  end
end
