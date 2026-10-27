defmodule Palee.Application.PasswordResetByEmailTest do
  @moduledoc "ADR-206: the reset link emailed to a verified address; handlers stay the fallback."
  use Palee.DataCase, async: false
  use Palee.EmailCase

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0, add_membership: 3]

  alias Palee.Application.{LoginUser, PasswordRecovery}
  alias Palee.Email.LinkTokens
  alias Palee.Identity
  alias Palee.Identity.{Login, PasswordResetLogEntry, PasswordResetRequest}
  alias Palee.TestFixtures

  setup do
    person = TestFixtures.user_fixture(%{nickname: "forgetful", email: "forgetful@example.com"})
    :ok = Identity.mark_email_verified(person.login_id, "forgetful@example.com")

    {organization, owner, _context} = organization_fixture()
    add_membership(organization, person, :member)

    %{person: Identity.find_by_id(person.id), owner: owner, organization: organization}
  end

  defp token_from(message) do
    [_, token] = Regex.run(~r"/reset-password#token=([A-Za-z0-9_-]{43})", message.text)
    token
  end

  defp requests, do: Repo.all(PasswordResetRequest)

  defp log_events, do: PasswordResetLogEntry |> Repo.all() |> Enum.map(& &1.event)

  defp backdate_emails(seconds) do
    Repo.query!(
      "UPDATE email_messages SET inserted_at = inserted_at - make_interval(secs => $1)",
      [seconds]
    )
  end

  defp attach_anomalies do
    ref = make_ref()
    test = self()

    :telemetry.attach(
      "password-reset-anomaly-#{inspect(ref)}",
      [:palee, :auth, :anomaly],
      fn _event, _measurements, metadata, _config -> send(test, {:anomaly, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach("password-reset-anomaly-#{inspect(ref)}") end)
  end

  describe "asking for a reset" do
    test "a verified email gets a one-hour link by email, and no handler is bothered", ctx do
      assert :ok = PasswordRecovery.request("@forgetful")

      message =
        assert_email_enqueued(
          kind: :password_reset,
          to: "forgetful@example.com",
          category: :security,
          login_id: ctx.person.login_id
        )

      assert message.text =~ "/reset-password#token="
      refute message.text =~ "?token="
      assert message.html =~ "Choose a new password"

      assert {:ok, link} = LinkTokens.peek(:password_reset, token_from(message))
      assert link.target_email == "forgetful@example.com"
      assert_in_delta DateTime.diff(link.expires_at, DateTime.utc_now()), 3600, 5

      assert requests() == []
      assert "link_emailed" in log_events()
    end

    test "the email follows the person's language", ctx do
      Repo.update_all(from(u in "users", where: u.id == type(^ctx.person.id, :binary_id)),
        set: [preferred_locale: "el"]
      )

      :ok = PasswordRecovery.request("forgetful@example.com", locale: "de")
      message = assert_email_enqueued(kind: :password_reset)
      assert message.locale == "el"
      assert message.subject =~ "Επαναφορά κωδικού"
    end

    test "an unverified email goes to the handlers, as before" do
      person = TestFixtures.user_fixture(%{nickname: "unsure", email: "unsure@example.com"})
      {organization, _owner, _context} = organization_fixture()
      add_membership(organization, person, :member)

      assert :ok = PasswordRecovery.request("unsure")
      refute_email_enqueued(kind: :password_reset)
      assert [%{login_id: login_id}] = requests()
      assert login_id == person.login_id
    end

    test "\"I can't access my email\" goes to the handlers even when verified", ctx do
      assert :ok = PasswordRecovery.request("forgetful", cant_access_email: true)
      refute_email_enqueued(kind: :password_reset)
      assert [%{login_id: login_id}] = requests()
      assert login_id == ctx.person.login_id
      assert [%{state: :open}] = PasswordRecovery.inbox(ctx.owner)
    end

    test "a suppressed address falls back to the handlers" do
      {:ok, _suppression} = Palee.Email.suppress("forgetful@example.com", :bounce)

      assert :ok = PasswordRecovery.request("forgetful")
      refute_email_enqueued(kind: :password_reset)
      assert [_request] = requests()
    end

    test "an unknown account sends nothing and files nothing" do
      assert :ok = PasswordRecovery.request("nobody@example.com")
      assert :ok = PasswordRecovery.request("@nobody")
      assert :ok = PasswordRecovery.request("")
      assert enqueued_emails() == []
      assert requests() == []
    end
  end

  describe "limits" do
    test "one email every 10 minutes and five a day per login; the rest is an anomaly" do
      attach_anomalies()

      :ok = PasswordRecovery.request("forgetful")
      :ok = PasswordRecovery.request("forgetful@example.com")
      assert length(enqueued_emails(kind: :password_reset)) == 1
      assert_receive {:anomaly, %{reason: "password_reset_throttled"}}
      assert "throttled" in log_events()

      for _ <- 2..5 do
        backdate_emails(11 * 60)
        :ok = PasswordRecovery.request("forgetful")
      end

      assert length(enqueued_emails(kind: :password_reset)) == 5

      backdate_emails(11 * 60)
      :ok = PasswordRecovery.request("forgetful")
      assert length(enqueued_emails(kind: :password_reset)) == 5
      assert_receive {:anomaly, %{reason: "password_reset_throttled"}}

      # A throttled request never files a handler request either.
      assert requests() == []
    end

    test "a throttled request keeps the link already in the inbox working" do
      :ok = PasswordRecovery.request("forgetful")
      token = token_from(assert_email_enqueued(kind: :password_reset))
      :ok = PasswordRecovery.request("forgetful")
      assert {:ok, _link} = LinkTokens.peek(:password_reset, token)
    end

    test "one client files at most three handler requests a day" do
      attach_anomalies()
      key = :crypto.strong_rand_bytes(32)
      {organization, _owner, _context} = organization_fixture()

      people =
        for n <- 1..4 do
          person = TestFixtures.user_fixture(%{nickname: "flood#{n}", email: "f#{n}@example.com"})
          add_membership(organization, person, :member)
          person
        end

      for person <- people,
          do: :ok = PasswordRecovery.request(person.handle, requester_key: key)

      assert length(requests()) == 3
      assert_receive {:anomaly, %{reason: "password_reset_handler_cap"}}

      # Another client is not affected.
      :ok = PasswordRecovery.request("forgetful", cant_access_email: true)
      assert length(requests()) == 4
    end
  end

  describe "using the emailed link" do
    setup ctx do
      :ok = PasswordRecovery.request("forgetful")
      Map.put(ctx, :token, token_from(assert_email_enqueued(kind: :password_reset)))
    end

    test "inspecting never spends the link; completing does, once", ctx do
      assert {:ok, %{expires_at: _}} = PasswordRecovery.inspect_link(ctx.token)
      assert {:ok, %{expires_at: _}} = PasswordRecovery.inspect_link(ctx.token)

      assert :ok = PasswordRecovery.complete(ctx.token, "new pass")
      assert {:error, :used_reset_link} = PasswordRecovery.inspect_link(ctx.token)
      assert {:error, :used_reset_link} = PasswordRecovery.complete(ctx.token, "other pass")

      assert {:ok, _session} = LoginUser.call(%{identifier: "forgetful", password: "new pass"})
      assert {:error, _} = LoginUser.call(%{identifier: "forgetful", password: "other pass"})
      assert "completed" in log_events()
    end

    test "the link expires after one hour", ctx do
      later = DateTime.add(DateTime.utc_now(), 61 * 60, :second)
      assert {:error, :expired_reset_link} = PasswordRecovery.inspect_link(ctx.token, later)

      assert {:error, :expired_reset_link} =
               PasswordRecovery.complete(ctx.token, "new pass", later)

      assert {:error, _} = LoginUser.call(%{identifier: "forgetful", password: "new pass"})
    end

    test "a weak password leaves the link unspent", ctx do
      assert {:error, :weak_password} = PasswordRecovery.complete(ctx.token, "ab")
      assert {:ok, _} = PasswordRecovery.inspect_link(ctx.token)
    end

    test "the link and the password change commit together", ctx do
      # The address changed since the link was sent: nothing happens at all.
      Repo.update_all(from(l in Login, where: l.id == ^ctx.person.login_id),
        set: [email: "moved@example.com"]
      )

      assert {:error, :invalid_reset_link} = PasswordRecovery.complete(ctx.token, "new pass")
      assert {:ok, _} = PasswordRecovery.inspect_link(ctx.token)
      assert {:error, _} = LoginUser.call(%{identifier: "forgetful", password: "new pass"})
      assert {:ok, _} = LoginUser.call(%{identifier: "forgetful", password: "S3cur3P@ss!42"})
    end

    test "completing bumps the security version and closes an open handler request", ctx do
      :ok = PasswordRecovery.request("forgetful", cant_access_email: true)
      assert [_request] = requests()
      before = Identity.find_by_id(ctx.person.id)

      assert :ok = PasswordRecovery.complete(ctx.token, "new pass")

      after_reset = Identity.find_by_id(ctx.person.id)
      assert after_reset.security_version > before.security_version
      assert requests() == []
    end

    test "completing proves the address", ctx do
      Repo.update_all(from(l in Login, where: l.id == ^ctx.person.login_id),
        set: [email_verified_at: nil]
      )

      assert :ok = PasswordRecovery.complete(ctx.token, "new pass")
      assert Identity.email_verified?(Identity.find_by_id(ctx.person.id))
    end

    test "racing submits spend the link exactly once", ctx do
      results =
        1..4
        |> Enum.map(fn n ->
          Task.async(fn -> PasswordRecovery.complete(ctx.token, "pass #{n}x") end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(results, &(&1 == :ok)) == 1
    end
  end

  describe "handler links (ADR-187) keep working" do
    test "inspect and complete a handler-issued 24-hour link", ctx do
      :ok = PasswordRecovery.request("forgetful", cant_access_email: true)
      [%{id: id}] = PasswordRecovery.inbox(ctx.owner)
      {:ok, %{token: token, expires_at: expires_at}} = PasswordRecovery.issue_link(ctx.owner, id)

      assert_in_delta DateTime.diff(expires_at, DateTime.utc_now()), 24 * 3600, 5
      assert {:ok, %{expires_at: ^expires_at}} = PasswordRecovery.inspect_link(token)
      assert {:error, :weak_password} = PasswordRecovery.complete(token, "ab")
      assert :ok = PasswordRecovery.complete(token, "new pass")
      assert {:error, :invalid_reset_link} = PasswordRecovery.inspect_link(token)
      assert {:error, :invalid_reset_link} = PasswordRecovery.complete(token, "again pass")
    end

    test "an unknown token is invalid" do
      assert {:error, :invalid_reset_link} = PasswordRecovery.inspect_link("nope")
      assert {:error, :invalid_reset_link} = PasswordRecovery.complete("nope", "new pass")
    end
  end
end
