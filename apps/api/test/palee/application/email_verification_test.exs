defmodule Palee.Application.EmailVerificationTest do
  use Palee.DataCase, async: true
  use Palee.EmailCase

  alias Palee.Application.{EmailVerification, RegisterUser}
  alias Palee.Identity

  defp register!(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    params =
      Map.merge(
        %{
          "handle" => "verify_#{unique}",
          "display_name" => "Ελένη",
          "password" => "S3cur3P@ss!42",
          "role" => "member",
          "email" => "verify_#{unique}@example.com",
          "age_confirmed" => true
        },
        attrs
      )

    {:ok, %{user: user}} = RegisterUser.call(params)
    {user, params}
  end

  defp token_from(message) do
    [_, token] = Regex.run(~r{/verify-email#token=([A-Za-z0-9_-]+)}, message.text)
    token
  end

  describe "sign-up" do
    test "a new login gets one verify_email link in its language" do
      {user, _params} = register!(%{"preferred_locale" => "el"})

      message =
        assert_email_enqueued(kind: :verify_email, to: user.email, login_id: user.login_id)

      assert message.category == "account"
      assert message.locale == "el"
      assert message.subject == "Επιβεβαίωσε τη διεύθυνση email σου"
      assert message.text =~ "Γεια σου Ελένη,"
      assert message.html =~ "/verify-email#token="
      assert message.idempotency_key == "verify_email:#{user.login_id}:sign_up"
      refute Identity.email_verified?(Identity.find_by_id(user.id))
    end

    test "adding a profile to an existing login sends nothing more" do
      {user, params} = register!()

      {:ok, %{user: second}} =
        RegisterUser.call(%{params | "handle" => "#{params["handle"]}_2"})

      assert second.login_id == user.login_id
      assert [_one] = enqueued_emails(kind: :verify_email, login_id: user.login_id)
    end

    test "the dev flag verifies instead of emailing" do
      Application.put_env(:palee, :auto_verify_email, true)
      on_exit(fn -> Application.delete_env(:palee, :auto_verify_email) end)

      {user, _params} = register!()

      refute_email_enqueued(kind: :verify_email, login_id: user.login_id)
      assert Identity.email_verified?(Identity.find_by_id(user.id))
    end
  end

  describe "verify/2" do
    test "spends the link once and marks the login verified" do
      {user, _params} = register!()
      token = token_from(assert_email_enqueued(kind: :verify_email, login_id: user.login_id))

      assert :ok = EmailVerification.verify(token)
      assert Identity.email_verified?(Identity.find_by_id(user.id))
      assert {:error, :used} = EmailVerification.verify(token)
    end

    test "refuses unknown, expired and outdated links" do
      assert {:error, :invalid} = EmailVerification.verify("nope")
      assert {:error, :invalid} = EmailVerification.verify("")

      {user, _params} = register!()
      token = token_from(assert_email_enqueued(kind: :verify_email, login_id: user.login_id))
      later = DateTime.add(DateTime.utc_now(), 49 * 3600, :second)
      assert {:error, :expired} = EmailVerification.verify(token, later)

      {other, _params} = register!()

      {:ok, _message} =
        EmailVerification.send_verification(other,
          to: "someone.else@example.com",
          now: DateTime.add(DateTime.utc_now(), 120, :second)
        )

      outdated =
        token_from(assert_email_enqueued(kind: :verify_email, to: "someone.else@example.com"))

      assert {:error, :email_mismatch} = EmailVerification.verify(outdated)
      refute Identity.email_verified?(Identity.find_by_id(other.id))
    end
  end

  describe "resend/2" do
    test "is throttled with a retry-after, and a new link replaces the old one" do
      {user, _params} = register!()
      first = token_from(assert_email_enqueued(kind: :verify_email, login_id: user.login_id))

      assert {:error, {:throttled, seconds}} = EmailVerification.resend(user)
      assert seconds in 1..60
      # The throttled request did not kill the link already in the inbox.
      assert {:ok, _token} = Palee.Email.LinkTokens.peek(:verify_email, first)

      later = DateTime.add(DateTime.utc_now(), 61, :second)
      assert {:ok, :sent} = EmailVerification.resend(user, now: later)

      tokens =
        Enum.map(enqueued_emails(kind: :verify_email, login_id: user.login_id), &token_from/1)

      assert [newest] = tokens -- [first]

      assert {:error, :invalid} = Palee.Email.LinkTokens.peek(:verify_email, first)
      assert :ok = EmailVerification.verify(newest, later)

      assert {:ok, :already_verified} =
               EmailVerification.resend(Identity.find_by_id(user.id), now: later)
    end

    test "stops after five links a day until the oldest is a day old" do
      {user, _params} = register!()
      start = DateTime.utc_now()

      for minute <- 2..5 do
        assert {:ok, :sent} =
                 EmailVerification.resend(user, now: DateTime.add(start, minute * 61, :second))
      end

      sixth = DateTime.add(start, 10 * 61, :second)
      assert {:error, {:throttled, seconds}} = EmailVerification.resend(user, now: sixth)
      assert seconds > 23 * 3600
    end
  end
end
