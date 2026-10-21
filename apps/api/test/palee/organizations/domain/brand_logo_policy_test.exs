defmodule Palee.Organizations.Domain.BrandLogoPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.BrandLogoPolicy
  alias Palee.Organizations.{PlatformContext, TenantContext}

  @org_a "11111111-1111-4111-8111-111111111111"
  @org_b "22222222-2222-4222-8222-222222222222"
  @object_id "33333333-3333-4333-8333-333333333333"
  @user "44444444-4444-4444-8444-444444444444"
  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, "IHDR">>
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, 0, 16, "JFIF", 0, 1, 1, 0, 0>>
  @webp <<"RIFF", 0, 0, 0, 0, "WEBP", "VP8 ">>
  @svg "<svg xmlns=\"http://www.w3.org/2000/svg\"><script>alert(1)</script></svg>"
  @now ~U[2026-10-12 10:00:00.000000Z]

  defp tenant(role, organization_id \\ @org_a) do
    %TenantContext{
      organization: %{id: organization_id},
      membership: %{},
      account: %{},
      organization_id: organization_id,
      membership_id: @object_id,
      user_id: @user,
      role: role
    }
  end

  describe "authorize/2" do
    test "tenant owners and admins act on their own organization only" do
      for role <- [:owner, :admin] do
        assert {:ok, %{organization_id: @org_a, user_id: @user, scope: :tenant}} =
                 BrandLogoPolicy.authorize(tenant(role), nil)

        assert {:ok, %{organization_id: @org_a}} = BrandLogoPolicy.authorize(tenant(role), @org_a)
        assert {:error, :forbidden} = BrandLogoPolicy.authorize(tenant(role), @org_b)
      end
    end

    test "other tenant roles are forbidden" do
      for role <- [:coach, :member, :athlete] do
        assert {:error, :forbidden} = BrandLogoPolicy.authorize(tenant(role), nil)
      end
    end

    test "vendors act on the named organization" do
      context = %PlatformContext{account: %{}, vendor: %{}, user_id: @user}

      assert {:ok, %{organization_id: @org_b, scope: :vendor}} =
               BrandLogoPolicy.authorize(context, @org_b)

      assert {:error, :not_found} = BrandLogoPolicy.authorize(context, "not-a-uuid")
      assert {:error, :not_found} = BrandLogoPolicy.authorize(context, nil)
    end

    test "no context fails closed" do
      assert {:error, :organization_context_required} = BrandLogoPolicy.authorize(nil, @org_a)
    end
  end

  describe "validate_request/2" do
    test "accepts PNG, JPEG and WebP up to 2 MiB" do
      for type <- ~w(image/png image/jpeg image/webp) do
        assert {:ok, ^type} = BrandLogoPolicy.validate_request(type, 2 * 1_024 * 1_024)
      end
    end

    test "rejects SVG, other types, empty and oversized uploads" do
      assert {:error, :invalid_brand_logo_upload} =
               BrandLogoPolicy.validate_request("image/svg+xml", 100)

      assert {:error, :invalid_brand_logo_upload} =
               BrandLogoPolicy.validate_request("image/gif", 100)

      assert {:error, :invalid_brand_logo_upload} =
               BrandLogoPolicy.validate_request("image/png", 0)

      assert {:error, :invalid_brand_logo_upload} =
               BrandLogoPolicy.validate_request("image/png", 2 * 1_024 * 1_024 + 1)

      assert {:error, :invalid_brand_logo_upload} = BrandLogoPolicy.validate_request(nil, "10")
    end
  end

  describe "object keys" do
    test "keys are tenant-prefixed with a uuid name and type extension" do
      assert BrandLogoPolicy.object_key(@org_a, @object_id, "image/jpeg") ==
               "organizations/#{@org_a}/branding/logo/#{@object_id}.jpg"
    end

    test "owned_key? accepts only keys this policy issues for the organization" do
      key = BrandLogoPolicy.object_key(@org_a, @object_id, "image/png")

      assert BrandLogoPolicy.owned_key?(@org_a, key)
      refute BrandLogoPolicy.owned_key?(@org_b, key)
      refute BrandLogoPolicy.owned_key?(@org_a, "organizations/#{@org_a}/branding/logo/x.png")

      refute BrandLogoPolicy.owned_key?(
               @org_a,
               "organizations/#{@org_a}/branding/logo/#{@object_id}.svg"
             )

      refute BrandLogoPolicy.owned_key?(
               @org_a,
               "organizations/#{@org_a}/branding/logo/../../#{@org_b}/branding/logo/#{@object_id}.png"
             )

      refute BrandLogoPolicy.owned_key?(@org_a, "organizations/#{@org_a}/purge/#{@object_id}.png")
      refute BrandLogoPolicy.owned_key?(@org_a, "users/#{@user}/avatars/#{@object_id}.png")
      refute BrandLogoPolicy.owned_key?(@org_a, nil)
    end
  end

  describe "validate_object/2" do
    test "magic bytes must match an allowed type and the key extension" do
      png_key = BrandLogoPolicy.object_key(@org_a, @object_id, "image/png")
      jpg_key = BrandLogoPolicy.object_key(@org_a, @object_id, "image/jpeg")
      webp_key = BrandLogoPolicy.object_key(@org_a, @object_id, "image/webp")

      assert {:ok, "image/png"} =
               BrandLogoPolicy.validate_object(png_key, %{head: @png, byte_size: 10})

      assert {:ok, "image/jpeg"} =
               BrandLogoPolicy.validate_object(jpg_key, %{head: @jpeg, byte_size: 10})

      assert {:ok, "image/webp"} =
               BrandLogoPolicy.validate_object(webp_key, %{head: @webp, byte_size: 10})

      assert {:error, :unsupported_brand_logo_type} =
               BrandLogoPolicy.validate_object(png_key, %{head: @jpeg, byte_size: 10})
    end

    test "SVG and other non-raster payloads are rejected" do
      key = BrandLogoPolicy.object_key(@org_a, @object_id, "image/png")

      assert {:error, :unsupported_brand_logo_type} =
               BrandLogoPolicy.validate_object(key, %{head: @svg, byte_size: byte_size(@svg)})

      assert {:error, :unsupported_brand_logo_type} =
               BrandLogoPolicy.validate_object(key, %{head: "GIF89a", byte_size: 6})
    end

    test "size limits are enforced on the stored object" do
      key = BrandLogoPolicy.object_key(@org_a, @object_id, "image/png")

      assert {:error, {:brand_logo_too_large, 2_097_153}} =
               BrandLogoPolicy.validate_object(key, %{head: @png, byte_size: 2_097_153})

      assert {:error, :brand_logo_upload_missing} =
               BrandLogoPolicy.validate_object(key, %{head: "", byte_size: 0})
    end
  end

  describe "change_event/2 and superseded_key/3" do
    test "classifies uploads, replacements, removals and no-ops" do
      empty = %{brand_logo_object_key: nil, brand_logo_url: nil}
      external = %{brand_logo_object_key: nil, brand_logo_url: "https://cdn.example/logo.png"}
      uploaded = %{brand_logo_object_key: "k1", brand_logo_url: "https://media/k1"}

      assert BrandLogoPolicy.change_event(empty, "k1") == "organization_logo_uploaded"
      assert BrandLogoPolicy.change_event(external, "k1") == "organization_logo_replaced"
      assert BrandLogoPolicy.change_event(uploaded, "k2") == "organization_logo_replaced"
      assert BrandLogoPolicy.change_event(uploaded, "k1") == nil
      assert BrandLogoPolicy.change_event(uploaded, nil) == "organization_logo_removed"
      assert BrandLogoPolicy.change_event(external, nil) == "organization_logo_removed"
      assert BrandLogoPolicy.change_event(empty, nil) == nil
    end

    test "only an owned, different previous key is superseded" do
      old = BrandLogoPolicy.object_key(@org_a, @object_id, "image/png")
      new = BrandLogoPolicy.object_key(@org_a, Ecto.UUID.generate(), "image/png")

      assert BrandLogoPolicy.superseded_key(@org_a, old, new) == old
      assert BrandLogoPolicy.superseded_key(@org_a, old, nil) == old
      assert BrandLogoPolicy.superseded_key(@org_a, old, old) == nil
      assert BrandLogoPolicy.superseded_key(@org_b, old, nil) == nil
      assert BrandLogoPolicy.superseded_key(@org_a, nil, new) == nil
    end

    test "event metadata carries ids and keys only" do
      actor = %{organization_id: @org_a, user_id: @user, scope: :tenant}
      current = %{brand_logo_object_key: "k1", brand_logo_url: "https://media/k1"}

      assert BrandLogoPolicy.event_metadata(actor, current, "k2", @now) == %{
               actor_scope: "tenant",
               object_key: "k2",
               previous_object_key: "k1",
               previous_external_url: false,
               changed_at: "2026-10-12T10:00:00.000000Z"
             }
    end
  end
end
