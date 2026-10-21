defmodule PaleeWeb.UserSocketTenantContextTest do
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures
  require Phoenix.ChannelTest
  alias Palee.Infrastructure.Auth.Guardian
  alias Palee.Organizations
  alias PaleeWeb.UserSocket
  alias PaleeWeb.{NotificationChannel, ScheduleChannel}

  test "socket can connect without tenant context for user-wide notification channels" do
    user = user_fixture()

    {:ok, token, _claims} =
      Guardian.encode_and_sign(user, %{"sv" => user.security_version || 1}, token_type: "access")

    assert {:ok, socket} =
             Phoenix.ChannelTest.connect(UserSocket, %{
               "token" => token
             })

    refute Map.has_key?(socket.assigns, :tenant_context)

    assert {:ok, _reply, _socket} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               NotificationChannel,
               "notifications:#{user.id}"
             )
  end

  test "socket organization context is resolved from current membership, not JWT claims" do
    user = user_fixture()
    {:ok, first} = Organizations.create_organization(%{name: "First Context"})
    {:ok, second} = Organizations.create_organization(%{name: "Second Context"})

    for organization <- [first, second] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: :member,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    forged_claims = %{
      "sv" => user.security_version || 1,
      "memberships" => [
        %{"organization_id" => Ecto.UUID.generate(), "role" => "owner"}
      ]
    }

    {:ok, token, _claims} =
      Guardian.encode_and_sign(user, forged_claims, token_type: "access")

    assert {:ok, first_socket} =
             Phoenix.ChannelTest.connect(UserSocket, %{
               "token" => token,
               "organization_slug" => first.slug
             })

    assert first_socket.assigns.tenant_context.organization_id == first.id
    assert first_socket.assigns.tenant_context.role == :member

    assert {:ok, second_socket} =
             Phoenix.ChannelTest.connect(UserSocket, %{
               "token" => token,
               "organization_slug" => second.slug
             })

    assert second_socket.assigns.tenant_context.organization_id == second.id

    {:ok, foreign} = Organizations.create_organization(%{name: "Foreign Context"})

    assert :error =
             Phoenix.ChannelTest.connect(UserSocket, %{
               "token" => token,
               "organization_slug" => foreign.slug
             })
  end

  test "channel join revalidates a membership that became stale after socket connection" do
    user = user_fixture()
    {:ok, organization} = Organizations.create_organization(%{name: "Stale Membership Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, token, _claims} =
      Guardian.encode_and_sign(user, %{"sv" => user.security_version || 1}, token_type: "access")

    assert {:ok, socket} =
             Phoenix.ChannelTest.connect(UserSocket, %{
               "token" => token,
               "organization_slug" => organization.slug
             })

    {:ok, _suspended} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: :member,
        status: :suspended,
        joined_at: DateTime.utc_now()
      })

    assert {:error, %{reason: "unauthorized"}} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               ScheduleChannel,
               "schedule:#{organization.id}"
             )
  end

  test "a socket connected before a slug rename keeps working, and the retired slug connects (ADR-122)" do
    user = user_fixture()
    vendor = user_fixture()
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
    {:ok, platform} = Organizations.resolve_platform_context(vendor)
    {:ok, organization} = Organizations.create_organization(%{name: "Socket Rename Gym"})
    old_slug = organization.slug

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, token, _claims} =
      Guardian.encode_and_sign(user, %{"sv" => user.security_version || 1}, token_type: "access")

    assert {:ok, socket} =
             Phoenix.ChannelTest.connect(UserSocket, %{
               "token" => token,
               "organization_slug" => old_slug
             })

    assert {:ok, _result} =
             Organizations.rename_organization_slug(platform, organization.id, %{
               "slug" => "socket-renamed-gym",
               "confirmation" => old_slug
             })

    # Topics are keyed by organization id, and the join-time revalidation
    # resolves the (now retired) slug held in the socket's context.
    assert {:ok, _reply, _socket} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               ScheduleChannel,
               "schedule:#{organization.id}"
             )

    assert {:ok, renamed_socket} =
             Phoenix.ChannelTest.connect(UserSocket, %{
               "token" => token,
               "organization_slug" => old_slug
             })

    assert renamed_socket.assigns.tenant_context.organization.slug == "socket-renamed-gym"
  end
end
