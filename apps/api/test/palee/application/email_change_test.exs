defmodule Palee.Application.EmailChangeTest do
  @moduledoc "ADR-207: an email change waits for its link; revert locks further changes."
  use Palee.DataCase, async: false
  use Palee.EmailCase

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Application.EmailChange
  alias Palee.Email.LinkTokens
  alias Palee.Identity
  alias Palee.Identity.{Login, PendingEmailChange}
  alias Palee.Repo

  @password "S3cur3P@ss!42"

  setup do
    %{user: user_fixture()}
  end

  defp token_from(message) do
    [_, token] = Regex.run(~r/#token=([A-Za-z0-9_-]+)/, message.text)
    token
  end

  defp request!(user, email, now \\ DateTime.utc_now()) do
    {:ok, status} = EmailChange.request(user, email, @password, now)
    message = assert_email_enqueued(kind: :email_change_confirm, to: email, status: :queued)
    {status, token_from(message)}
  end

  defp login(user), do: Repo.get!(Login, user.login_id)

  describe "request/4" do
    test "a wrong or missing current password changes nothing", %{user: user} do
      assert {:error, :invalid_current_password} =
               EmailChange.request(user, "new@box.test", "wrong")

      assert {:error, :invalid_current_password} = EmailChange.request(user, "new@box.test", nil)
      refute_email_enqueued(kind: :email_change_confirm)
      assert EmailChange.status(user).pending == nil
    end

    test "an invalid or unchanged address is refused", %{user: user} do
      assert {:error, :invalid_email} = EmailChange.request(user, "not an email", @password)

      assert {:error, :email_unchanged} =
               EmailChange.request(user, " #{String.upcase(user.email)} ", @password)
    end

    test "keeps the old address and mails a 24 h link to the new one", %{user: user} do
      now = DateTime.utc_now()
      {status, _token} = request!(user, " New@Box.test ", now)

      assert status.pending.email == "new@box.test"
      assert DateTime.diff(status.pending.expires_at, now) == 24 * 60 * 60
      assert login(user).email == user.email

      message = assert_email_enqueued(kind: :email_change_confirm, to: "new@box.test")
      assert message.category == "security"
      assert message.login_id == user.login_id
      assert message.text =~ "/confirm-email-change#token="
      refute message.text =~ user.email
      refute message.html =~ user.email
    end

    test "an address that already has an account gets the same answer", %{user: user} do
      other = user_fixture()
      {status, _token} = request!(user, other.email)
      assert status.pending.email == other.email
    end

    test "a second request replaces the first and its link", %{user: user} do
      {_status, first} = request!(user, "one@box.test")
      {status, _second} = request!(user, "two@box.test")

      assert status.pending.email == "two@box.test"
      assert Repo.aggregate(where(PendingEmailChange, login_id: ^user.login_id), :count) == 1
      assert {:error, :invalid_link} = EmailChange.confirm(first)
    end
  end

  describe "confirm/2" do
    test "makes the new address the verified login email and revokes every session", %{
      user: user
    } do
      {:ok, second} =
        Identity.add_profile(user.login_id, %{
          handle: "second_#{System.unique_integer([:positive])}",
          role: :athlete
        })

      before = login(user)
      {_status, token} = request!(user, "new@box.test")

      assert {:ok, %{login_id: login_id, email: "new@box.test"}} = EmailChange.confirm(token)
      assert login_id == user.login_id

      after_change = login(user)
      assert after_change.email == "new@box.test"
      assert after_change.email_verified_at
      assert after_change.security_version == before.security_version + 1
      assert Identity.find_by_id(second.id).security_version > second.security_version
      assert EmailChange.status(user).pending == nil

      revert =
        Repo.one!(
          from t in Palee.Email.LinkToken,
            where: t.login_id == ^user.login_id and t.purpose == "email_change_revert"
        )

      assert revert.target_email == user.email
      assert revert.metadata == %{"new_email" => "new@box.test"}
      assert DateTime.diff(revert.expires_at, DateTime.utc_now()) > 6 * 24 * 60 * 60

      assert Identity.find_by_email("new@box.test").login_id == user.login_id
      assert Identity.find_by_email(user.email) == nil
      assert {:error, :invalid_link} = EmailChange.confirm(token)
    end

    test "fails clearly when the address was taken meanwhile", %{user: user} do
      {_status, token} = request!(user, "taken@box.test")
      user_fixture(%{email: "Taken@box.test"})

      assert {:error, :email_unavailable} = EmailChange.confirm(token)
      assert login(user).email == user.email
      assert EmailChange.status(user).pending == nil
    end

    test "an expired link or pending change is refused", %{user: user} do
      past = DateTime.add(DateTime.utc_now(), -25 * 60 * 60, :second)
      {_status, token} = request!(user, "late@box.test", past)

      assert {:error, :expired_link} = EmailChange.confirm(token)
      assert EmailChange.status(user).pending == nil
      assert login(user).email == user.email
    end

    test "a cancelled change's link no longer works", %{user: user} do
      {_status, token} = request!(user, "new@box.test")
      assert :ok = EmailChange.cancel(user)
      assert EmailChange.status(user).pending == nil
      assert {:error, :invalid_link} = EmailChange.confirm(token)
      assert login(user).email == user.email
    end

    test "junk is an invalid link" do
      assert {:error, :invalid_link} = EmailChange.confirm("junk")
      assert {:error, :invalid_link} = EmailChange.confirm(nil)
    end
  end

  describe "resend/2" do
    test "mails a fresh link and restarts the clock; the old link stops", %{user: user} do
      now = DateTime.utc_now()
      {_status, first} = request!(user, "new@box.test", now)

      later = DateTime.add(now, 120, :second)
      assert {:ok, status} = EmailChange.resend(user, later)
      assert DateTime.diff(status.pending.expires_at, now) == 24 * 60 * 60 + 120
      [latest | _] = enqueued_emails(kind: :email_change_confirm, to: "new@box.test")
      second = token_from(latest)

      assert {:error, :invalid_link} = EmailChange.confirm(first)
      assert {:ok, _} = EmailChange.confirm(second)
    end

    test "is throttled right after the request", %{user: user} do
      request!(user, "new@box.test")
      assert {:error, :throttled} = EmailChange.resend(user)
    end

    test "needs a pending change", %{user: user} do
      assert {:error, :no_pending_email_change} = EmailChange.resend(user)
    end
  end

  describe "revert/2" do
    defp changed!(user) do
      {_status, token} = request!(user, "new@box.test")
      {:ok, _} = EmailChange.confirm(token)

      {:ok, raw, _token} =
        LinkTokens.issue(:email_change_revert, user.login_id,
          target_email: user.email,
          metadata: %{"new_email" => "new@box.test"}
        )

      raw
    end

    test "restores the old address, verified, revokes sessions and locks changes", %{user: user} do
      raw = changed!(user)
      version = login(user).security_version

      {:ok, _pending} =
        Identity.EmailChangeStore.put_pending(
          user.login_id,
          "again@box.test",
          DateTime.utc_now(),
          DateTime.add(DateTime.utc_now(), 3600, :second)
        )

      assert {:ok, %{email: email}} = EmailChange.revert(raw)
      assert email == user.email

      restored = login(user)
      assert restored.email == user.email
      assert restored.email_verified_at
      assert restored.security_version == version + 1
      assert EmailChange.status(user).pending == nil

      locked_until = EmailChange.status(user).locked_until
      assert DateTime.diff(locked_until, DateTime.utc_now()) > 6 * 24 * 60 * 60
      assert {:error, :invalid_link} = EmailChange.revert(raw)

      account = Identity.find_by_id(user.id)

      assert {:error, {:email_change_locked, ^locked_until}} =
               EmailChange.request(account, "other@box.test", @password)
    end

    test "a password reset lifts the lock", %{user: user} do
      {:ok, _} = EmailChange.revert(changed!(user))
      assert :ok = Identity.reset_login_password(user.login_id, "N3wP@ssword!")

      assert EmailChange.status(user).locked_until == nil
      account = Identity.find_by_id(user.id)
      assert {:ok, _status} = EmailChange.request(account, "other@box.test", "N3wP@ssword!")
    end

    test "the lock ends after 7 days", %{user: user} do
      {:ok, _} = EmailChange.revert(changed!(user))
      later = DateTime.add(DateTime.utc_now(), 7 * 24 * 60 * 60 + 60, :second)
      account = Identity.find_by_id(user.id)

      assert EmailChange.status(account, later).locked_until == nil
      assert {:ok, _} = EmailChange.request(account, "other@box.test", @password, later)
    end

    test "fails when the old address was taken meanwhile", %{user: user} do
      raw = changed!(user)
      user_fixture(%{email: user.email})

      assert {:error, :email_unavailable} = EmailChange.revert(raw)
      assert login(user).email == "new@box.test"
    end

    test "an expired revert link is refused", %{user: user} do
      {:ok, raw, _token} =
        LinkTokens.issue(:email_change_revert, user.login_id,
          target_email: user.email,
          now: DateTime.add(DateTime.utc_now(), -8 * 24 * 60 * 60, :second)
        )

      assert {:error, :expired_link} = EmailChange.revert(raw)
    end
  end
end
