defmodule Palee.Application.SecurityNoticeWiringTest do
  @moduledoc "ADR-208: the existing account paths that send a security notice."
  use Palee.DataCase, async: true
  use Palee.EmailCase

  alias Palee.Application.{
    AccountProfiles,
    PasswordRecovery,
    SignOutAllDevices,
    UpdateProfile
  }

  alias Palee.TestFixtures

  @password "S3cur3P@ss!42"

  setup do
    %{person: TestFixtures.user_fixture(%{nickname: "wired", email: "wired@example.com"})}
  end

  test "a new password in Settings sends :password_changed, never the password", %{
    person: person
  } do
    {:ok, _user} =
      UpdateProfile.call(person, %{
        "password" => "brand new pass",
        "current_password" => @password
      })

    message = assert_email_enqueued(kind: :security_password_changed, to: "wired@example.com")
    refute message.text =~ "brand new pass"
    refute message.html =~ "brand new pass"

    # Other profile edits send nothing.
    {:ok, _user} = UpdateProfile.call(person, %{"preferred_locale" => "de"})
    assert [_one] = enqueued_emails(kind: :security_password_changed)
  end

  test "new recovery codes are told, without the codes", %{person: person} do
    {:ok, codes} = PasswordRecovery.generate_codes(person, @password)

    message = assert_email_enqueued(kind: :security_recovery_codes_regenerated)
    for code <- codes, do: refute(message.text =~ code)
  end

  test "using a code is told, and so is running low at two codes left", %{person: person} do
    {:ok, codes} = PasswordRecovery.generate_codes(person, @password)
    {to_use, [_last_two_a, _last_two_b]} = Enum.split(codes, length(codes) - 2)
    [first | rest] = to_use

    :ok = PasswordRecovery.redeem_code("wired", first, "fresh pass 1")
    message = assert_email_enqueued(kind: :security_recovery_code_used)
    refute message.text =~ first
    refute_email_enqueued(kind: :security_recovery_codes_running_low)

    for code <- rest, do: :ok = PasswordRecovery.redeem_code("wired", code, "fresh pass 2")

    low = assert_email_enqueued(kind: :security_recovery_codes_running_low)
    assert low.text =~ "You have only two unused recovery codes left."
    assert low.text =~ "/me/settings#security"
  end

  test "signing out every device from Settings is told", %{person: person} do
    assert :ok = SignOutAllDevices.call(person)
    assert_email_enqueued(kind: :security_signed_out_everywhere, to: "wired@example.com")
  end

  test "adding a profile to the login is told, naming the new profile", %{person: person} do
    {:ok, _profile} = AccountProfiles.add(person, %{handle: "wired_two", role: "member"})

    message = assert_email_enqueued(kind: :security_profile_added, to: "wired@example.com")
    assert message.text =~ "@wired_two"
  end
end
