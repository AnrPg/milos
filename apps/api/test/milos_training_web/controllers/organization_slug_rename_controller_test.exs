defmodule MilosTrainingWeb.OrganizationSlugRenameControllerTest do
  @moduledoc "ADR-122: platform slug rename endpoints and API tenant resolution by a retired slug."
  use MilosTrainingWeb.ConnCase, async: false

  import Ecto.Query
  import MilosTraining.TestFixtures

  alias MilosTraining.Organizations
  alias MilosTraining.Organizations.{OrganizationProvisioningEvent, OrganizationSlugAlias}
  alias MilosTraining.Repo

  setup do
    vendor = user_fixture()
    member = user_fixture()
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)

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

    %{vendor: vendor, member: member, organization: organization}
  end

  defp rename(conn, ctx, params) do
    conn
    |> put_bearer_token(ctx.vendor)
    |> patch("/api/platform/organizations/#{ctx.organization.id}/slug", params)
  end

  test "shows the impact summary before a rename", %{conn: conn} = ctx do
    response =
      conn
      |> put_bearer_token(ctx.vendor)
      |> get("/api/platform/organizations/#{ctx.organization.id}/slug-impact")
      |> json_response(200)

    assert response["organization"]["slug"] == "harbor-gym"
    assert response["canonical_path"] == "/org/harbor-gym"
    assert response["active_member_count"] == 1
    assert response["pending_invitation_count"] == 0
    assert response["purge_open"] == false
    assert response["previous_slugs"] == []
  end

  test "renames the slug with a typed confirmation and audits it", %{conn: conn} = ctx do
    response =
      conn
      |> rename(ctx, %{slug: "north-harbor", confirmation: "harbor-gym"})
      |> json_response(200)

    assert response["organization"]["slug"] == "north-harbor"
    assert response["canonical_path"] == "/org/north-harbor"
    assert response["previous_slug"] == "harbor-gym"
    assert [%{"slug" => "harbor-gym", "retired_at" => _}] = response["previous_slugs"]

    assert Repo.exists?(
             from event in OrganizationProvisioningEvent,
               where:
                 event.organization_id == ^ctx.organization.id and
                   event.event == "organization_slug_renamed"
           )
  end

  test "rejects a wrong confirmation, an invalid slug and a taken slug", %{conn: conn} = ctx do
    assert %{"code" => "slug_confirmation_mismatch"} =
             conn
             |> rename(ctx, %{slug: "north-harbor", confirmation: "nope"})
             |> json_response(422)

    assert %{"code" => "invalid_slug"} =
             build_conn()
             |> rename(ctx, %{slug: "North Harbor", confirmation: "harbor-gym"})
             |> json_response(422)

    {:ok, _other} = Organizations.create_organization(%{name: "Other", slug: "other-gym"})

    assert %{"code" => "slug_taken"} =
             build_conn()
             |> rename(ctx, %{slug: "other-gym", confirmation: "harbor-gym"})
             |> json_response(409)

    refute Repo.exists?(OrganizationSlugAlias)
  end

  test "is vendor-only", %{conn: conn} = ctx do
    assert %{"code" => "vendor_required"} =
             conn
             |> put_bearer_token(ctx.member)
             |> patch("/api/platform/organizations/#{ctx.organization.id}/slug", %{
               slug: "north-harbor",
               confirmation: "harbor-gym"
             })
             |> json_response(403)
  end

  test "tenant API requests by a retired slug resolve and name the canonical slug",
       %{conn: conn} = ctx do
    conn |> rename(ctx, %{slug: "north-harbor", confirmation: "harbor-gym"}) |> json_response(200)

    old =
      build_conn()
      |> put_bearer_token(ctx.member)
      |> get("/api/org/harbor-gym/me/training-log/entries")

    assert json_response(old, 200)
    assert get_resp_header(old, "x-organization-canonical-slug") == ["north-harbor"]

    current =
      build_conn()
      |> put_bearer_token(ctx.member)
      |> get("/api/org/north-harbor/me/training-log/entries")

    assert json_response(current, 200)
    assert get_resp_header(current, "x-organization-canonical-slug") == []
  end

  test "a retired slug does not let a non-member in", %{conn: conn} = ctx do
    conn |> rename(ctx, %{slug: "north-harbor", confirmation: "harbor-gym"}) |> json_response(200)
    outsider = user_fixture()

    assert %{"code" => "organization_context_not_found"} =
             build_conn()
             |> put_bearer_token(outsider)
             |> get("/api/org/harbor-gym/me/training-log/entries")
             |> json_response(404)
  end

  test "the public alias lookup answers only for retired slugs", %{conn: conn} = ctx do
    conn |> rename(ctx, %{slug: "north-harbor", confirmation: "harbor-gym"}) |> json_response(200)

    assert %{
             "slug" => "harbor-gym",
             "canonical_slug" => "north-harbor",
             "canonical_path" => "/org/north-harbor"
           } =
             build_conn()
             |> get("/api/organization-slug-aliases/harbor-gym")
             |> json_response(200)

    for slug <- ["north-harbor", "never-existed"] do
      assert %{"code" => "organization_slug_alias_not_found"} =
               build_conn()
               |> get("/api/organization-slug-aliases/#{slug}")
               |> json_response(404)
    end
  end
end
