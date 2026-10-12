defmodule MilosTraining.Application.OrganizationLogoTest do
  @moduledoc "ADR-103 tenant logo upload flow against the in-memory object store."

  use MilosTraining.DataCase, async: false

  import Ecto.Query
  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{
    FinalizeOrganizationLogo,
    GetOrganizationBranding,
    RemoveOrganizationLogo,
    RequestOrganizationLogoUpload,
    TenantObjectStorage
  }

  alias MilosTraining.{Organizations, RLSCase}
  alias MilosTraining.Organizations.{OrganizationProvisioningEvent, OrganizationSetting}
  alias MilosTraining.TestSupport.MemoryObjectStore

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, "IHDR", 0, 0, 0, 1>>
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, 0, 16, "JFIF", 0, 1, 1, 0, 0, 1>>

  setup do
    org_a = organization_with(:owner)
    org_b = organization_with(:admin)
    vendor = user_fixture()
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
    {:ok, platform} = Organizations.resolve_platform_context(vendor)

    %{a: org_a, b: org_b, platform: platform, vendor: vendor}
  end

  describe "tenant owner/admin flow" do
    test "request -> upload -> finalize stores the key, derived URL and an audit event", ctx do
      %{context: context, organization: organization} = ctx.a

      assert {:ok, upload} =
               RequestOrganizationLogoUpload.call(context, nil, %{
                 "content_type" => "image/png",
                 "byte_size" => byte_size(@png)
               })

      assert upload.key =~ ~r|^organizations/#{organization.id}/branding/logo/[0-9a-f-]{36}\.png$|
      assert upload.required_headers == %{"content-type" => "image/png"}
      assert upload.max_bytes == 2 * 1_024 * 1_024

      client_put(upload.key, @png)

      assert {:ok, settings} = FinalizeOrganizationLogo.call(context, nil, upload.key)
      assert settings.brand_logo_object_key == upload.key
      assert settings.brand_logo_url == "https://media.test/branding/#{upload.key}"

      assert [event] = events(organization.id)
      assert event.event == "organization_logo_uploaded"
      assert event.vendor_user_id == context.user_id
      assert event.metadata["actor_scope"] == "tenant"
      assert event.metadata["object_key"] == upload.key
      assert event.metadata["previous_object_key"] == nil

      assert Map.keys(event.metadata) |> Enum.sort() ==
               ~w(actor_scope changed_at object_key previous_external_url previous_object_key)

      assert {:ok, %{brand_logo_url: url}} = GetOrganizationBranding.call(context)
      assert url == settings.brand_logo_url
    end

    test "replacing deletes the previous object; finalizing twice is a no-op", ctx do
      %{context: context, organization: organization} = ctx.a
      first = upload!(context, "image/png", @png)
      assert {:ok, _} = FinalizeOrganizationLogo.call(context, nil, first)

      second = upload!(context, "image/jpeg", @jpeg)
      assert {:ok, settings} = FinalizeOrganizationLogo.call(context, nil, second)
      assert settings.brand_logo_object_key == second
      assert MemoryObjectStore.get(:branding, first) == :error
      assert {:ok, _} = MemoryObjectStore.get(:branding, second)

      assert {:ok, ^settings} = FinalizeOrganizationLogo.call(context, nil, second)

      assert events(organization.id) |> Enum.map(& &1.event) ==
               ["organization_logo_uploaded", "organization_logo_replaced"]
    end

    test "removal clears settings, deletes the object and is audited", ctx do
      %{context: context, organization: organization} = ctx.a
      key = upload!(context, "image/png", @png)
      assert {:ok, _} = FinalizeOrganizationLogo.call(context, nil, key)

      assert {:ok, settings} = RemoveOrganizationLogo.call(context)
      assert settings.brand_logo_object_key == nil
      assert settings.brand_logo_url == nil
      assert MemoryObjectStore.get(:branding, key) == :error

      assert {:ok, _} = RemoveOrganizationLogo.call(context)

      assert events(organization.id) |> Enum.map(& &1.event) ==
               ["organization_logo_uploaded", "organization_logo_removed"]
    end

    test "invalid bytes are rejected and the uploaded object is deleted", ctx do
      %{context: context} = ctx.a
      svg = ~s|<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>|
      key = upload!(context, "image/png", svg)

      assert {:error, :unsupported_brand_logo_type} =
               FinalizeOrganizationLogo.call(context, nil, key)

      assert MemoryObjectStore.get(:branding, key) == :error
      assert {:ok, %{brand_logo_object_key: nil}} = GetOrganizationBranding.call(context)

      oversized = upload!(context, "image/png", @png <> :binary.copy(<<0>>, 2 * 1_024 * 1_024))

      assert {:error, {:brand_logo_too_large, _size}} =
               FinalizeOrganizationLogo.call(context, nil, oversized)
    end

    test "requests for SVG, unknown types or oversized files are refused", ctx do
      for params <- [
            %{"content_type" => "image/svg+xml", "byte_size" => 100},
            %{"content_type" => "image/gif", "byte_size" => 100},
            %{"content_type" => "image/png", "byte_size" => 2 * 1_024 * 1_024 + 1}
          ] do
        assert {:error, :invalid_brand_logo_upload} =
                 RequestOrganizationLogoUpload.call(ctx.a.context, nil, params)
      end
    end

    test "a missing upload cannot be finalized", ctx do
      %{context: context, organization: organization} = ctx.a
      key = "organizations/#{organization.id}/branding/logo/#{Ecto.UUID.generate()}.png"

      assert {:error, :brand_logo_upload_missing} =
               FinalizeOrganizationLogo.call(context, nil, key)
    end

    test "non-admin tenant members are forbidden", ctx do
      member = user_fixture()
      add_member(ctx.a.organization, member, :member)
      {:ok, context} = Organizations.resolve_tenant_context(member, ctx.a.organization.slug)

      assert {:error, :forbidden} =
               RequestOrganizationLogoUpload.call(context, nil, %{
                 "content_type" => "image/png",
                 "byte_size" => 10
               })

      assert {:error, :forbidden} = RemoveOrganizationLogo.call(context)
    end
  end

  describe "two-tenant isolation" do
    test "org A's admin cannot finalize a key under org B's prefix", ctx do
      b_key = upload!(ctx.b.context, "image/png", @png)

      assert {:error, :brand_logo_key_forbidden} =
               FinalizeOrganizationLogo.call(ctx.a.context, nil, b_key)

      # Naming org B explicitly from an org A context is refused too.
      assert {:error, :forbidden} =
               FinalizeOrganizationLogo.call(ctx.a.context, ctx.b.organization.id, b_key)

      # Org B's object and settings are untouched.
      assert {:ok, @png} = MemoryObjectStore.get(:branding, b_key)
      assert {:ok, %{brand_logo_object_key: nil}} = GetOrganizationBranding.call(ctx.b.context)
      assert {:ok, %{brand_logo_object_key: nil}} = GetOrganizationBranding.call(ctx.a.context)
      assert events(ctx.a.organization.id) == []
      assert events(ctx.b.organization.id) == []
    end

    test "a traversal key that starts with org A's prefix is refused", ctx do
      b_key = upload!(ctx.b.context, "image/png", @png)

      traversal =
        "organizations/#{ctx.a.organization.id}/branding/logo/../../../" <> b_key

      assert {:error, :brand_logo_key_forbidden} =
               FinalizeOrganizationLogo.call(ctx.a.context, nil, traversal)
    end

    test "a previous key outside the prefix is never deleted", ctx do
      b_key = upload!(ctx.b.context, "image/png", @png)

      # Simulate a corrupted settings row pointing at another tenant's object.
      Repo.update_all(
        from(s in OrganizationSetting, where: s.organization_id == ^ctx.a.organization.id),
        set: [brand_logo_object_key: b_key, brand_logo_url: "https://media.test/x"]
      )

      assert {:ok, _} = RemoveOrganizationLogo.call(ctx.a.context)
      assert {:ok, @png} = MemoryObjectStore.get(:branding, b_key)
    end
  end

  describe "vendor via platform console" do
    test "vendors upload, replace and remove any organization's logo", ctx do
      org_id = ctx.b.organization.id

      assert {:ok, upload} =
               RequestOrganizationLogoUpload.call(ctx.platform, org_id, %{
                 content_type: "image/jpeg",
                 byte_size: byte_size(@jpeg)
               })

      client_put(upload.key, @jpeg)
      assert {:ok, settings} = FinalizeOrganizationLogo.call(ctx.platform, org_id, upload.key)
      assert settings.brand_logo_object_key == upload.key

      assert [event] = events(org_id)
      assert event.vendor_user_id == ctx.vendor.id
      assert event.metadata["actor_scope"] == "vendor"

      assert {:ok, %{brand_logo_url: nil}} = RemoveOrganizationLogo.call(ctx.platform, org_id)
    end

    test "unknown organizations are not found", ctx do
      assert {:error, :not_found} =
               RequestOrganizationLogoUpload.call(ctx.platform, Ecto.UUID.generate(), %{
                 "content_type" => "image/png",
                 "byte_size" => 10
               })
    end

    test "manual brand_logo_url edits are refused while an uploaded logo is managed", ctx do
      %{context: context, organization: organization} = ctx.a
      key = upload!(context, "image/png", @png)
      assert {:ok, _} = FinalizeOrganizationLogo.call(context, nil, key)

      assert {:error, %Ecto.Changeset{errors: [brand_logo_url: _]}} =
               Organizations.update_organization_settings(ctx.platform, organization.id, %{
                 "brand_logo_url" => "https://cdn.example.test/other.png"
               })

      assert {:ok, _} =
               Organizations.update_organization_settings(ctx.platform, organization.id, %{
                 "brand_name" => "Renamed"
               })
    end
  end

  describe "tenant purge" do
    test "uploaded logos are inventoried and purged with the tenant's objects", ctx do
      %{context: context, organization: organization} = ctx.a
      key = upload!(context, "image/png", @png)
      assert {:ok, _} = FinalizeOrganizationLogo.call(context, nil, key)

      assert {:ok, %{documents: documents}} = TenantObjectStorage.inventory(organization.id, [])
      assert Enum.any?(documents, &(&1.key == key))

      assert {:ok, %{deleted_objects: 1}} =
               TenantObjectStorage.purge_tenant_objects(organization.id, [])

      assert MemoryObjectStore.get(:branding, key) == :error
    end
  end

  describe "under real row level security" do
    test "a tenant admin's finalize and audit insert pass as the runtime role", ctx do
      RLSCase.ensure_runtime_role!()
      %{organization: organization, owner: owner} = ctx.a
      Repo.query!("SET LOCAL ROLE #{RLSCase.runtime_role()}")

      {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
      key = upload!(context, "image/png", @png)
      assert {:ok, settings} = FinalizeOrganizationLogo.call(context, nil, key)
      assert settings.brand_logo_object_key == key
      assert {:ok, _} = RemoveOrganizationLogo.call(context)

      Repo.query!("RESET ROLE")
      assert events(organization.id) |> length() == 2
    end

    test "a tenant admin cannot insert logo events for another organization", ctx do
      RLSCase.ensure_runtime_role!()
      Repo.query!("SET LOCAL ROLE #{RLSCase.runtime_role()}")

      assert_raise Postgrex.Error, ~r/row-level security/, fn ->
        MilosTraining.Infrastructure.Tenancy.RepoContext.run(ctx.a.context, fn ->
          %OrganizationProvisioningEvent{}
          |> OrganizationProvisioningEvent.changeset(%{
            organization_id: ctx.b.organization.id,
            vendor_user_id: ctx.a.context.user_id,
            event: "organization_logo_uploaded",
            metadata: %{}
          })
          |> Repo.insert()
        end)
      end
    end
  end

  defp organization_with(role) do
    owner = user_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Logo Gym #{System.unique_integer([:positive])}"})

    add_member(organization, owner, role)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    %{organization: organization, owner: owner, context: context}
  end

  defp add_member(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end

  defp upload!(context, content_type, body) do
    {:ok, %{key: key}} =
      RequestOrganizationLogoUpload.call(context, nil, %{
        "content_type" => content_type,
        "byte_size" => min(byte_size(body), 2 * 1_024 * 1_024)
      })

    client_put(key, body)
    key
  end

  defp client_put(key, body), do: :ok = MemoryObjectStore.put_object(:branding, key, body, "x")

  defp events(organization_id) do
    from(e in OrganizationProvisioningEvent,
      where: e.organization_id == ^organization_id and like(e.event, "organization_logo_%"),
      order_by: [asc: e.inserted_at]
    )
    |> Repo.all()
  end
end
