defmodule MilosTraining.Organizations.InvitationEmailBindingTest do
  @moduledoc """
  F-10: an invitation issued to a specific address must only be redeemable by
  an account holding that address. The digest was previously computed at issue
  time and never checked - accounts carried no email at all, so there was
  nothing to compare against.
  """
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Identity
  alias MilosTraining.Organizations
  alias MilosTraining.Organizations.Domain.InvitationEmail
  alias MilosTraining.TestFixtures

  setup do
    owner = TestFixtures.admin_fixture()
    {:ok, organization} = Organizations.create_organization(%{name: "Invite Gym"})

    {:ok, _membership} =
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

  describe "InvitationEmail" do
    test "normalizes case and surrounding whitespace before digesting" do
      assert InvitationEmail.digest("  Nikos@Example.COM ") ==
               InvitationEmail.digest("nikos@example.com")
    end

    test "treats a blank address as no binding at all" do
      assert InvitationEmail.digest(nil) == nil
      assert InvitationEmail.digest("") == nil
      assert InvitationEmail.digest("   ") == nil
    end

    test "an unbound invitation matches anyone, including an account with no email" do
      assert InvitationEmail.matches?(nil, "anyone@example.com")
      assert InvitationEmail.matches?(nil, nil)
    end

    test "a bound invitation never matches an account without an email" do
      refute InvitationEmail.matches?(InvitationEmail.digest("a@example.com"), nil)
    end
  end

  test "an account holding the invited address may redeem", %{context: context} do
    {:ok, %{token: token}} =
      Organizations.issue_invitation(context, %{role: "member", intended_email: "Invited@Example.com"})

    invitee = register_with_email("invited@example.com")

    assert {:ok, redemption} = Organizations.redeem_invitation(token, invitee.id)
    assert redemption.membership.user_id == invitee.id
  end

  test "casing and whitespace differences still redeem", %{context: context} do
    {:ok, %{token: token}} =
      Organizations.issue_invitation(context, %{role: "member", intended_email: "invited@example.com"})

    invitee = register_with_email("  INVITED@Example.com  ")

    assert {:ok, _redemption} = Organizations.redeem_invitation(token, invitee.id)
  end

  test "a different account cannot redeem, and the invitation stays usable", %{context: context} do
    {:ok, %{token: token}} =
      Organizations.issue_invitation(context, %{role: "member", intended_email: "invited@example.com"})

    intruder = register_with_email("someone.else@example.com")

    assert {:error, :invitation_email_mismatch} =
             Organizations.redeem_invitation(token, intruder.id)

    # A rejected attempt must not consume the invitation - otherwise a wrong
    # guess would deny the legitimate invitee.
    invitee = register_with_email("invited@example.com")
    assert {:ok, _redemption} = Organizations.redeem_invitation(token, invitee.id)
  end

  test "an account with no email cannot redeem a bound invitation", %{context: context} do
    {:ok, %{token: token}} =
      Organizations.issue_invitation(context, %{role: "member", intended_email: "invited@example.com"})

    emailless = TestFixtures.user_fixture(%{role: :member})

    assert {:error, :invitation_email_mismatch} =
             Organizations.redeem_invitation(token, emailless.id)
  end

  test "an invitation issued without an address stays open to any account", %{context: context} do
    {:ok, %{token: token}} = Organizations.issue_invitation(context, %{role: "member"})

    emailless = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, _redemption} = Organizations.redeem_invitation(token, emailless.id)
  end

  test "email addresses are unique across accounts, case-insensitively" do
    register_with_email("taken@example.com")

    assert {:error, changeset} =
             Identity.register(%{
               nickname: "dup_#{System.unique_integer([:positive])}",
               password: "S3cur3P@ss!",
               role: :member,
               email: "TAKEN@example.com"
             })

    assert changeset.errors[:email]
  end

  defp register_with_email(email) do
    {:ok, user} =
      Identity.register(%{
        nickname: "invitee_#{System.unique_integer([:positive])}",
        password: "S3cur3P@ss!",
        role: :member,
        email: email
      })

    user
  end
end
