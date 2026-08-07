defmodule MilosTrainingWeb.TenancyInvariantsTest do
  @moduledoc """
  Regression tests for tenancy properties that are already correct.

  `08-test-gap-plan.md` items 13, 15, 17, 19, 20 and 21 each note "confirmed
  already correct - add a regression test". Untested correct behaviour is
  exactly what silently regresses, so these lock the properties in rather than
  leaving them resting on review.
  """
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Organizations
  alias MilosTraining.Organizations.Domain.InvitationPolicy

  import MilosTraining.TestFixtures

  describe "platform (vendor) privilege is unreachable from the tenant surface" do
    # Gap-plan #15: no HTTP path grants vendor status. Asserted against the
    # router itself rather than by probing URLs, so adding such a route fails
    # here regardless of what path someone picks.
    test "no route reaches a vendor-granting action" do
      granting_actions = [:grant_vendor, :create_vendor, :grant_platform_owner]

      offending =
        MilosTrainingWeb.Router.__routes__()
        |> Enum.filter(&(&1.plug_opts in granting_actions))

      assert offending == [],
             "vendor granting must stay shell-only (mix milos.platform.grant_vendor), " <>
               "found routes: #{inspect(Enum.map(offending, & &1.path))}"
    end

    # Gap-plan #19: a global :admin role must not imply platform ownership.
    test "an account with the global admin role cannot reach platform endpoints", %{conn: conn} do
      admin = admin_fixture()

      response =
        conn
        |> put_bearer_token(admin)
        |> get("/api/platform/organizations")

      assert response.status in [401, 403]
    end
  end

  describe "invitations" do
    setup do
      owner = admin_fixture()
      {:ok, organization} = Organizations.create_organization(%{name: "Invariant Gym"})

      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: owner.id,
          role: :owner,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
      {:ok, owner: owner, organization: organization, context: context}
    end

    # Gap-plan #20: role is normalized against a fixed enum, so an invented
    # role cannot be smuggled through.
    test "a role outside the enum is rejected rather than passed through", %{context: context} do
      assert {:error, _} = Organizations.issue_invitation(context, %{role: "platform_owner"})
      assert {:error, _} = Organizations.issue_invitation(context, %{role: "vendor"})
      assert {:error, _} = Organizations.issue_invitation(context, %{role: "superuser"})
    end

    # Gap-plan #17: the organization is taken from the acting context, never
    # from the request, so an admin cannot issue into someone else's gym.
    test "the invitation's organization comes from the context, not the params", %{
      context: context,
      organization: organization
    } do
      {:ok, other_org} = Organizations.create_organization(%{name: "Invariant Gym B"})

      {:ok, %{invitation: invitation}} =
        Organizations.issue_invitation(context, %{
          role: "member",
          organization_id: other_org.id
        })

      assert invitation.organization_id == organization.id
      refute invitation.organization_id == other_org.id
    end

    # Gap-plan #21: expiry is enforced at redemption.
    test "an expired invitation is not redeemable" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)

      refute InvitationPolicy.redeemable?(
               %{expires_at: past, redeemed_at: nil, revoked_at: nil},
               DateTime.utc_now()
             )

      assert InvitationPolicy.redeemable?(
               %{
                 expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
                 redeemed_at: nil,
                 revoked_at: nil
               },
               DateTime.utc_now()
             )
    end

    test "an expired invitation is rejected end to end", %{context: context} do
      # 300s is the shortest lifetime the schema allows ("between 5 minutes and
      # 7 days after issuance"), so redemption is attempted past that instead.
      {:ok, %{token: token}} =
        Organizations.issue_invitation(context, %{role: "member", lifetime_seconds: 300})

      redeemer = user_fixture(%{role: :member})

      assert {:error, :invalid_invitation} =
               Organizations.redeem_invitation(
                 token,
                 redeemer.id,
                 DateTime.add(DateTime.utc_now(), 600, :second)
               )
    end
  end

  # Gap-plan #13: the first organization created must hold no special runtime
  # privilege. The legacy organization is tenant #1, not a fallback.
  test "a later-created organization behaves identically to the first" do
    owner = admin_fixture()

    contexts =
      for name <- ["Parity Gym One", "Parity Gym Two"] do
        {:ok, organization} = Organizations.create_organization(%{name: name})

        {:ok, _} =
          Organizations.add_membership(%{
            organization_id: organization.id,
            user_id: owner.id,
            role: :owner,
            status: :active,
            joined_at: DateTime.utc_now()
          })

        {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
        context
      end

    for context <- contexts do
      assert {:ok, %{invitation: invitation}} =
               Organizations.issue_invitation(context, %{role: "member"})

      assert invitation.organization_id == context.organization_id
      assert context.role == :owner
    end

    [first, second] = contexts
    refute first.organization_id == second.organization_id
  end
end
