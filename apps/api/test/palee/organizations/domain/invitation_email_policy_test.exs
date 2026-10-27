defmodule Palee.Organizations.Domain.InvitationEmailPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.{InvitationEmail, InvitationEmailPolicy}

  @limits InvitationEmailPolicy.default_limits()

  test "parses pasted text and CSV into unique addresses, keeping what it skipped" do
    assert {["a@x.gr", "b@x.gr", "c@x.gr"], ["name", "nope"]} =
             InvitationEmailPolicy.parse_addresses(~s(name\n"A@x.gr";b@x.gr, a@x.gr nope\tc@x.gr))

    assert {["a@x.gr"], []} = InvitationEmailPolicy.parse_addresses(["a@x.gr", "A@X.GR", 7])
    assert {[], []} = InvitationEmailPolicy.parse_addresses(nil)
  end

  test "request size and daily caps" do
    assert :ok = InvitationEmailPolicy.check(200, %{organization: 0, inviter: 0}, @limits)

    assert {:error, :too_many_invitation_emails} =
             InvitationEmailPolicy.check(201, %{organization: 0, inviter: 0}, @limits)

    assert {:error, :invitation_email_cap_reached, 100} =
             InvitationEmailPolicy.check(150, %{organization: 200, inviter: 0}, @limits)

    assert {:error, :invitation_email_cap_reached, 0} =
             InvitationEmailPolicy.check(1, %{organization: 10, inviter: 200}, @limits)

    assert %{per_organization_day: 5, per_request: 200} =
             InvitationEmailPolicy.limits(per_organization_day: 5, unknown: 1)
  end

  test "delivery status from the outbox" do
    assert InvitationEmailPolicy.delivery_status(nil, false) == nil
    assert InvitationEmailPolicy.delivery_status("queued", false) == "queued"
    assert InvitationEmailPolicy.delivery_status("deferred", false) == "queued"
    assert InvitationEmailPolicy.delivery_status("sent", false) == "sent"
    assert InvitationEmailPolicy.delivery_status("sent", true) == "bounced"
    assert InvitationEmailPolicy.delivery_status("failed", false) == "failed"
    assert InvitationEmailPolicy.delivery_status("suppressed", false) == "suppressed"
  end

  test "a resend keeps the lifetime, within 5 minutes and 7 days" do
    at = ~U[2026-12-24 10:00:00Z]

    assert InvitationEmailPolicy.resend_lifetime(%{
             inserted_at: at,
             expires_at: DateTime.add(at, 86_400)
           }) ==
             86_400

    assert InvitationEmailPolicy.resend_lifetime(%{inserted_at: at, expires_at: at}) == 300
  end

  describe "InvitationEmail.redemption_proof/3" do
    test "the emailed link proves the inbox" do
      assert {:ok, :proof} =
               InvitationEmail.redemption_proof(
                 %{emailed_at: ~U[2026-12-24 10:00:00Z]},
                 false,
                 :proof
               )
    end

    test "a business's bound invitation needs a verified address" do
      bound = %{emailed_at: nil, email_verification_required: true}
      assert {:ok, nil} = InvitationEmail.redemption_proof(bound, true, :proof)

      assert {:error, :invitation_email_unverified} =
               InvitationEmail.redemption_proof(bound, false, :proof)
    end

    test "platform and older invitations need only the match" do
      assert {:ok, nil} =
               InvitationEmail.redemption_proof(
                 %{emailed_at: nil, email_verification_required: false},
                 false,
                 :proof
               )
    end
  end
end
