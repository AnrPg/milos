defmodule Palee.Identity.MarkEmailVerifiedTest do
  use Palee.DataCase, async: true

  alias Palee.Identity

  test "marks the login's current email and reports it on the account" do
    user = register!("verify.me@example.com")
    refute Identity.email_verified?(Identity.find_by_id(user.id))

    assert :ok = Identity.mark_email_verified(user.login_id, " Verify.Me@example.com ")
    assert Identity.email_verified?(Identity.find_by_id(user.id))
    # Idempotent.
    assert :ok = Identity.mark_email_verified(user.login_id, "verify.me@example.com")
  end

  test "refuses an address the login no longer has" do
    user = register!("first@example.com")

    assert {:error, :email_mismatch} =
             Identity.mark_email_verified(user.login_id, "other@example.com")

    refute Identity.email_verified?(Identity.find_by_id(user.id))
  end

  defp register!(email), do: Palee.TestFixtures.user_fixture(%{email: email})
end
