defmodule Palee.Organizations.InvitationEmailBindingTest do
  @moduledoc """
  F-10: an invitation issued to a specific address must only be redeemable by
  an account holding that address. The digest was previously computed at issue
  time and never checked - accounts carried no email at all, so there was
  nothing to compare against.
  """
  use Palee.DataCase, async: false

  alias Palee.Identity
  alias Palee.Organizations
  alias Palee.Organizations.Domain.InvitationEmail
  alias Palee.TestFixtures

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
      Organizations.issue_invitation(context, %{
        role: "member",
        intended_email: "Invited@Example.com"
      })

    invitee = register_with_email("invited@example.com")

    assert {:ok, redemption} = Organizations.redeem_invitation(token, invitee.id)
    assert redemption.membership.user_id == invitee.id
  end

  test "casing and whitespace differences still redeem", %{context: context} do
    {:ok, %{token: token}} =
      Organizations.issue_invitation(context, %{
        role: "member",
        intended_email: "invited@example.com"
      })

    invitee = register_with_email("  INVITED@Example.com  ")

    assert {:ok, _redemption} = Organizations.redeem_invitation(token, invitee.id)
  end

  test "a different account cannot redeem, and the invitation stays usable", %{context: context} do
    {:ok, %{token: token}} =
      Organizations.issue_invitation(context, %{
        role: "member",
        intended_email: "invited@example.com"
      })

    intruder = register_with_email("someone.else@example.com")

    assert {:error, :invitation_email_mismatch} =
             Organizations.redeem_invitation(token, intruder.id)

    # A rejected attempt must not consume the invitation - otherwise a wrong
    # guess would deny the legitimate invitee.
    invitee = register_with_email("invited@example.com")
    assert {:ok, _redemption} = Organizations.redeem_invitation(token, invitee.id)
  end

  test "an account whose address was never the invited one cannot redeem", %{context: context} do
    {:ok, %{token: token}} =
      Organizations.issue_invitation(context, %{
        role: "member",
        intended_email: "invited@example.com"
      })

    # Fixture accounts get a generated placeholder address, so this covers the
    # ordinary "some other member clicked the link" case.
    unrelated = TestFixtures.user_fixture(%{role: :member})

    assert {:error, :invitation_email_mismatch} =
             Organizations.redeem_invitation(token, unrelated.id)
  end

  test "an invitation issued without an address stays open to any account", %{context: context} do
    {:ok, %{token: token}} = Organizations.issue_invitation(context, %{role: "member"})

    unrelated = TestFixtures.user_fixture(%{role: :member})

    assert {:ok, _redemption} = Organizations.redeem_invitation(token, unrelated.id)
  end

  describe "ADR-209: proof of the inbox" do
    test "an unverified matching account cannot redeem, and the invitation stays usable",
         %{context: context} do
      {:ok, %{token: token}} =
        Organizations.issue_invitation(context, %{
          role: "member",
          intended_email: "invited@example.com"
        })

      unverified = register_with_email("invited@example.com", verified: false)

      assert {:error, :invitation_email_unverified} =
               Organizations.redeem_invitation(token, unverified.id)

      :ok = Identity.mark_email_verified(unverified.login_id, "invited@example.com")
      assert {:ok, _redemption} = Organizations.redeem_invitation(token, unverified.id)
    end

    test "an emailed invitation proves the inbox and marks the address verified",
         %{context: context} do
      {:ok, %{token: token}} =
        Organizations.issue_invitation(context, %{
          role: "member",
          intended_email: "invited@example.com",
          deliver_by_email: %{address: "invited@example.com", locale: "el"}
        })

      invitee = register_with_email("invited@example.com", verified: false)
      refute Identity.email_verified?(invitee)

      assert {:ok, redemption} = Organizations.redeem_invitation(token, invitee.id)
      assert redemption.invitation.emailed_at
      assert redemption.invitation.email_locale == "el"
      assert Identity.email_verified?(Identity.find_by_id(invitee.id))
    end

    test "an emailed invitation still refuses another address", %{context: context} do
      {:ok, %{token: token}} =
        Organizations.issue_invitation(context, %{
          role: "member",
          intended_email: "invited@example.com",
          deliver_by_email: %{address: "invited@example.com", locale: "en"}
        })

      other = register_with_email("other@example.com", verified: false)

      assert {:error, :invitation_email_mismatch} =
               Organizations.redeem_invitation(token, other.id)

      refute Identity.email_verified?(Identity.find_by_id(other.id))
    end

    test "mark_invitation_emailed is idempotent and turns on the inbox proof",
         %{context: context} do
      {:ok, %{token: token, invitation: invitation}} =
        Organizations.issue_invitation(context, %{
          role: "member",
          intended_email: "invited@example.com"
        })

      first = ~U[2026-12-24 10:00:00.000000Z]

      run = fn fun -> Palee.Infrastructure.Tenancy.RepoContext.run(context, fun) end
      assert :ok = run.(fn -> Organizations.mark_invitation_emailed(invitation.id, first) end)
      assert :ok = run.(fn -> Organizations.mark_invitation_emailed(invitation.id) end)

      assert {:error, :not_found} =
               run.(fn -> Organizations.mark_invitation_emailed(Ecto.UUID.generate()) end)

      invitee = register_with_email("invited@example.com", verified: false)
      assert {:ok, redemption} = Organizations.redeem_invitation(token, invitee.id)
      assert redemption.invitation.emailed_at == first
      assert Identity.email_verified?(Identity.find_by_id(invitee.id))
    end
  end

  test "email addresses are unique across accounts, case-insensitively" do
    register_with_email("taken@example.com")

    # ADR-187: a second login with the same email is refused; more profiles
    # on it are added from a signed-in session.
    assert {:error, :email_taken} =
             Identity.register(%{
               nickname: "dup_#{System.unique_integer([:positive])}",
               password: "S3cur3P@ss!42",
               role: :member,
               email: "TAKEN@example.com"
             })
  end

  test "email is mandatory for new accounts" do
    assert {:error, changeset} =
             Identity.register(%{
               nickname: "no_email_#{System.unique_integer([:positive])}",
               password: "S3cur3P@ss!42",
               role: :member
             })

    assert "can't be blank" in errors_on(changeset).email
  end

  test "a malformed address is rejected" do
    assert {:error, changeset} =
             Identity.register(%{
               nickname: "bad_email_#{System.unique_integer([:positive])}",
               password: "S3cur3P@ss!42",
               role: :member,
               email: "not-an-email"
             })

    assert changeset.errors[:email]
  end

  test "addresses are stored normalized so the digest comparison is stable" do
    user = register_with_email("  MiXeD@Example.COM ")
    assert user.email == "mixed@example.com"
  end

  # ADR-209: a business's bound invitation needs a verified address, so the
  # accounts here prove their inbox unless a test says otherwise.
  defp register_with_email(email, opts \\ []) do
    {:ok, user} =
      Identity.register(%{
        nickname: "invitee_#{System.unique_integer([:positive])}",
        password: "S3cur3P@ss!42",
        role: :member,
        email: email
      })

    if Keyword.get(opts, :verified, true),
      do: :ok = Identity.mark_email_verified(user.login_id, user.email)

    Identity.find_by_id(user.id)
  end
end
