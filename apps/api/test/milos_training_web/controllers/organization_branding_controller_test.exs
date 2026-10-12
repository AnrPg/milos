defmodule MilosTrainingWeb.OrganizationBrandingControllerTest do
  @moduledoc "ADR-111 tenant admin and platform logo upload endpoints."

  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Organizations
  alias MilosTraining.TestSupport.MemoryObjectStore

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, "IHDR", 0, 0, 0, 1>>

  setup do
    owner = user_fixture()
    organization = org_with(owner, :owner)
    other_admin = user_fixture()
    other = org_with(other_admin, :admin)
    vendor = user_fixture()
    {:ok, _} = Organizations.grant_vendor(vendor.id)

    %{
      owner: owner,
      organization: organization,
      other_admin: other_admin,
      other: other,
      vendor: vendor
    }
  end

  test "tenant owner uploads, finalizes, reads and removes the logo", ctx do
    base = "/api/org/#{ctx.organization.slug}/admin/branding"

    upload =
      ctx.conn
      |> put_bearer_token(ctx.owner)
      |> post("#{base}/logo/upload-url", %{content_type: "image/png", byte_size: 20})
      |> json_response(200)

    assert upload["key"] =~ "organizations/#{ctx.organization.id}/branding/logo/"
    assert upload["required_headers"] == %{"content-type" => "image/png"}
    :ok = MemoryObjectStore.put_object(:branding, upload["key"], @png, "image/png")

    finalized =
      ctx.conn
      |> put_bearer_token(ctx.owner)
      |> put("#{base}/logo", %{logo_key: upload["key"]})
      |> json_response(200)

    assert %{"brand_logo_uploaded" => true, "brand_logo_url" => url} = finalized["branding"]
    assert url == "https://media.test/branding/#{upload["key"]}"

    assert %{"branding" => %{"brand_logo_url" => ^url}} =
             ctx.conn |> put_bearer_token(ctx.owner) |> get(base) |> json_response(200)

    # Memberships (the shell/selector read model) expose the derived URL.
    memberships =
      ctx.conn |> put_bearer_token(ctx.owner) |> get("/api/memberships") |> json_response(200)

    assert Enum.any?(memberships, &(&1["settings"]["brand_logo_url"] == url))

    removed =
      ctx.conn
      |> put_bearer_token(ctx.owner)
      |> delete("#{base}/logo")
      |> json_response(200)

    assert removed["branding"] == %{
             "organization_id" => ctx.organization.id,
             "brand_name" => ctx.organization.name,
             "brand_logo_url" => nil,
             "brand_logo_uploaded" => false,
             "brand_primary_color" => nil
           }
  end

  test "SVG requests are rejected by the contract", ctx do
    conn =
      ctx.conn
      |> put_bearer_token(ctx.owner)
      |> post("/api/org/#{ctx.organization.slug}/admin/branding/logo/upload-url", %{
        content_type: "image/svg+xml",
        byte_size: 20
      })

    assert json_response(conn, 422)
  end

  test "an admin of another organization cannot finalize this organization's key", ctx do
    key = "organizations/#{ctx.organization.id}/branding/logo/#{Ecto.UUID.generate()}.png"
    :ok = MemoryObjectStore.put_object(:branding, key, @png, "image/png")

    conn =
      ctx.conn
      |> put_bearer_token(ctx.other_admin)
      |> put("/api/org/#{ctx.other.slug}/admin/branding/logo", %{logo_key: key})

    assert %{"code" => "brand_logo_key_forbidden"} = json_response(conn, 403)

    # ...nor reach this organization's admin routes at all.
    conn =
      ctx.conn
      |> put_bearer_token(ctx.other_admin)
      |> put("/api/org/#{ctx.organization.slug}/admin/branding/logo", %{logo_key: key})

    assert conn.status in [403, 404]
    assert {:ok, @png} = MemoryObjectStore.get(:branding, key)
  end

  test "non-admin members cannot use the tenant endpoints", ctx do
    member = user_fixture()
    add_member(ctx.organization, member, :member)

    conn =
      ctx.conn
      |> put_bearer_token(member)
      |> delete("/api/org/#{ctx.organization.slug}/admin/branding/logo")

    assert conn.status == 403
  end

  test "vendors manage any organization's logo from the platform console", ctx do
    base = "/api/platform/organizations/#{ctx.other.id}/branding/logo"

    upload =
      ctx.conn
      |> put_bearer_token(ctx.vendor)
      |> post("#{base}/upload-url", %{content_type: "image/png", byte_size: 20})
      |> json_response(200)

    :ok = MemoryObjectStore.put_object(:branding, upload["key"], @png, "image/png")

    assert %{"branding" => %{"brand_logo_uploaded" => true}} =
             ctx.conn
             |> put_bearer_token(ctx.vendor)
             |> put(base, %{logo_key: upload["key"]})
             |> json_response(200)

    listed =
      ctx.conn
      |> put_bearer_token(ctx.vendor)
      |> get("/api/platform/organizations")
      |> json_response(200)

    entry = Enum.find(listed["organizations"], &(&1["organization"]["id"] == ctx.other.id))
    assert entry["settings"]["brand_logo_uploaded"] == true

    assert %{"branding" => %{"brand_logo_url" => nil}} =
             ctx.conn |> put_bearer_token(ctx.vendor) |> delete(base) |> json_response(200)
  end

  test "non-vendors cannot use the platform endpoints", ctx do
    conn =
      ctx.conn
      |> put_bearer_token(ctx.owner)
      |> delete("/api/platform/organizations/#{ctx.organization.id}/branding/logo")

    assert %{"code" => "vendor_required"} = json_response(conn, 403)
  end

  defp org_with(user, role) do
    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Brand Gym #{System.unique_integer([:positive])}"
      })

    add_member(organization, user, role)
    organization
  end

  defp add_member(organization, user, role) do
    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
