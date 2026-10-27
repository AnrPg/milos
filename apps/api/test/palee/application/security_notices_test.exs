defmodule Palee.Application.SecurityNoticesTest do
  use Palee.DataCase, async: true
  use Palee.EmailCase

  alias Palee.Application.SecurityNotices
  alias Palee.Email.LinkTokens
  alias Palee.Email.Templates
  alias Palee.Identity
  alias Palee.TestFixtures

  @at ~U[2026-10-27 12:05:00Z]

  setup do
    person =
      TestFixtures.user_fixture(%{nickname: "noticed", email: "noticed@example.com"})

    %{person: person}
  end

  test "every event has its own registered security template" do
    for event <- SecurityNotices.events() do
      assert {:ok, module} = Templates.fetch(SecurityNotices.kind(event))
      assert module.category() == :security
    end
  end

  test "each event queues one notice to the login's address", %{person: person} do
    meta = %{
      at: @at,
      remaining: 1,
      profile: "@second",
      email: "new@example.com",
      revert_url: "https://palee.test/revert#token=r",
      undo_url: "https://palee.test/undo#token=u",
      scheduled_for: ~U[2026-11-03 12:00:00Z]
    }

    for event <- SecurityNotices.events() do
      assert :ok = SecurityNotices.notify(event, person, meta)

      message =
        assert_email_enqueued(kind: SecurityNotices.kind(event), to: "noticed@example.com")

      assert message.category == "security"
      assert message.login_id == person.login_id
      assert message.idempotency_key =~ "security_notice:#{event}:#{person.login_id}:"
      assert message.text =~ "Security notices can't be turned off."
      assert message.text =~ "27/10/2026 12:05 UTC"
      refute message.text =~ "S3cur3P@ss!42"
    end
  end

  test "what to do if it wasn't them: a working sign-out link and a new password", %{
    person: person
  } do
    :ok = SecurityNotices.notify(:password_changed, person, %{at: @at})
    message = assert_email_enqueued(kind: :security_password_changed)

    assert message.subject == "Your password was changed"
    assert message.text =~ "If this wasn't you, sign out everywhere right away"
    assert message.text =~ "/forgot-password"
    assert message.html =~ "Sign out everywhere"

    [_, token] = Regex.run(~r"/sign-out-everywhere#token=([A-Za-z0-9_-]{43})", message.text)
    assert {:ok, link} = LinkTokens.peek(:sign_out_everywhere, token)
    assert link.login_id == person.login_id
    assert link.target_email == "noticed@example.com"
  end

  test "two notices keep two working sign-out links", %{person: person} do
    :ok = SecurityNotices.notify(:password_changed, person, %{at: @at})
    :ok = SecurityNotices.notify(:profile_added, person, %{at: @at})

    for kind <- [:security_password_changed, :security_profile_added] do
      %{text: text} = assert_email_enqueued(kind: kind)
      [_, token] = Regex.run(~r"#token=([A-Za-z0-9_-]{43})", text)
      assert {:ok, _link} = LinkTokens.peek(:sign_out_everywhere, token)
    end
  end

  test "the moment is on the person's clock, named by its city", %{person: person} do
    {:ok, person} = Identity.update_time_zone(person.id, "Europe/Athens")
    :ok = SecurityNotices.notify(:new_sign_in, person, %{at: @at})

    assert %{text: text} = assert_email_enqueued(kind: :security_new_sign_in)
    assert text =~ "27/10/2026 14:05 (Athens)"
  end

  test "written in the person's language", %{person: person} do
    {:ok, person} = Identity.update_profile(person.id, %{preferred_locale: "el"})
    :ok = SecurityNotices.notify(:recovery_codes_regenerated, person, %{at: @at})

    message = assert_email_enqueued(kind: :security_recovery_codes_regenerated)
    assert message.locale == "el"
    assert message.subject == "Δημιουργήθηκαν νέοι κωδικοί ανάκτησης"
    assert message.text =~ "Οι ειδοποιήσεις ασφαλείας δεν απενεργοποιούνται."
  end

  test "the device and only the network part of the address are shown", %{person: person} do
    ua =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"

    :ok = SecurityNotices.notify(:new_sign_in, person, %{user_agent: ua, ip: {203, 0, 113, 77}})
    message = assert_email_enqueued(kind: :security_new_sign_in)

    assert message.text =~ "Device: Chrome on Windows"
    assert message.text =~ "IP address: 203.0.113.x"
    refute message.text =~ "203.0.113.77"
  end

  test "a device given as words is escaped in HTML", %{person: person} do
    :ok = SecurityNotices.notify(:new_sign_in, person, %{device: "<b>evil</b>"})
    message = assert_email_enqueued(kind: :security_new_sign_in)
    refute message.html =~ "<b>evil</b>"
    assert message.html =~ "&lt;b&gt;evil&lt;/b&gt;"
  end

  test "meta :to wins over the login's address", %{person: person} do
    :ok =
      SecurityNotices.notify(:email_changed, person, %{
        to: "old@example.com",
        email: "noticed@example.com",
        revert_url: "https://palee.test/revert#token=abc"
      })

    message = assert_email_enqueued(kind: :security_email_changed, to: "old@example.com")
    assert message.text =~ "was changed to noticed@example.com"
    assert message.text =~ "Undo this change:\nhttps://palee.test/revert#token=abc"
    refute_email_enqueued(kind: :security_email_changed, to: "noticed@example.com")
  end

  test "recovery codes running low points to Settings, without a sign-out link", %{
    person: person
  } do
    :ok = SecurityNotices.notify(:recovery_codes_running_low, person, %{remaining: 2})
    message = assert_email_enqueued(kind: :security_recovery_codes_running_low)

    assert message.text =~ "You have only two unused recovery codes left."
    assert message.text =~ "/me/settings#security"
    refute message.text =~ "sign-out-everywhere"
  end

  test "the same occurrence is sent once", %{person: person} do
    :ok = SecurityNotices.notify(:password_changed, person, %{occurrence: "abc"})
    :ok = SecurityNotices.notify(:password_changed, person, %{occurrence: "abc"})
    assert [_one] = enqueued_emails(kind: :security_password_changed)
  end

  test "an account without an address, or a refused send, is still :ok" do
    assert :ok = SecurityNotices.notify(:password_changed, %{id: Ecto.UUID.generate()})
    assert :ok = SecurityNotices.notify(:password_changed, %{email: "not an address"})
    assert enqueued_emails() == []
  end
end
