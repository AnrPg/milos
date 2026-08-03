defmodule MilosTrainingWeb.UserSocketTenantContextTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures
  require Phoenix.ChannelTest
  alias MilosTraining.Infrastructure.Auth.Guardian
  alias MilosTraining.Organizations
  alias MilosTrainingWeb.UserSocket

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
end
