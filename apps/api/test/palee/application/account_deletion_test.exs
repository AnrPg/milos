defmodule Palee.Application.AccountDeletionTest do
  @moduledoc "ADR-211: self-service deletion with password, emailed confirmation and a 7-day undo."
  use Palee.DataCase, async: false
  use Palee.EmailCase

  alias Palee.Application.{AccountDeletion, LoginUser}
  alias Palee.Email.LinkTokens
  alias Palee.Identity
  alias Palee.Identity.AccountDeletionStore
  alias Palee.Infrastructure.Security.MemoryTokenStore

  @password "S3cur3P@ss!42"
  @now ~U[2026-11-02 10:00:00.000000Z]

  setup do
    MemoryTokenStore.reset!()
    :ok
  end

  defp login_with_profiles(handles, opts \\ []) do
    unique = System.unique_integer([:positive])
    email = "deleter_#{unique}@placeholder.invalid"
    [first | rest] = handles

    {:ok, account} =
      Identity.register(%{
        nickname: "#{first}#{unique}",
        password: @password,
        role: :member,
        email: email
      })

    for handle <- rest do
      {:ok, _profile} =
        Identity.add_profile(account.login_id, %{
          handle: "#{handle}#{unique}",
          display_name: handle,
          role: :member,
          preferred_locale: "en"
        })
    end

    if Keyword.get(opts, :verified, true),
      do: :ok = Identity.mark_email_verified(account.login_id, email)

    Identity.find_by_id(account.id)
  end

  defp confirmation_token(email) do
    message = assert_email_enqueued(kind: :account_deletion_confirm, to: email)
    [_, token] = Regex.run(~r/#token=([A-Za-z0-9_-]{43})/, message.text)
    {message, token}
  end

  defp sign_in(identifier), do: LoginUser.call(%{identifier: identifier, password: @password})

  describe "request/3" do
    test "needs the login's password and a known scope" do
      account = login_with_profiles(["solo"])

      assert {:error, :invalid_password} =
               AccountDeletion.request(account, %{scope: "login", password: "wrong"}, @now)

      assert {:error, :invalid_scope} =
               AccountDeletion.request(account, %{scope: "everything", password: @password}, @now)

      refute_email_enqueued(kind: :account_deletion_confirm)
      assert AccountDeletionStore.for_login(account.login_id) == nil
    end

    test "a verified email gets a confirmation link; nothing is scheduled yet" do
      account = login_with_profiles(["main", "coach"])

      assert {:ok, %{status: :awaiting_confirmation, scope: :profile}} =
               AccountDeletion.request(
                 account,
                 %{"scope" => "profile", "password" => @password},
                 @now
               )

      {message, _token} = confirmation_token(account.email)
      assert message.category == "security"
      assert message.text =~ "You asked to delete your profile @#{account.handle}."
      assert message.text =~ "/account-deletion/confirm#token="
      assert message.text =~ "takes place in 7 days"
      refute message.text =~ @password

      # Still signs in while it waits for the link.
      assert {:ok, _tokens} = sign_in(account.email)
    end

    test "a second request replaces one awaiting its link" do
      account = login_with_profiles(["main", "coach"])
      {:ok, _} = AccountDeletion.request(account, %{scope: "profile", password: @password}, @now)
      later = DateTime.add(@now, 120, :second)
      {:ok, _} = AccountDeletion.request(account, %{scope: "login", password: @password}, later)

      assert %{scope: :login, status: :awaiting_confirmation} =
               AccountDeletionStore.for_login(account.login_id)
    end

    test "the last profile takes the login with it" do
      account = login_with_profiles(["solo"])

      assert {:ok, %{scope: :login}} =
               AccountDeletion.request(account, %{scope: "profile", password: @password}, @now)
    end

    test "without a verified email the typed address confirms and schedules at once" do
      account = login_with_profiles(["main"], verified: false)

      assert {:error, :confirmation_mismatch} =
               AccountDeletion.request(
                 account,
                 %{
                   scope: "login",
                   password: @password,
                   confirm_email: "other@placeholder.invalid"
                 },
                 @now
               )

      assert {:ok, %{status: :scheduled, scope: :login, scheduled_for: at}} =
               AccountDeletion.request(
                 account,
                 %{
                   scope: "login",
                   password: @password,
                   confirm_email: " #{String.upcase(account.email)} "
                 },
                 @now
               )

      assert at == DateTime.add(@now, 7 * 86_400, :second)
      refute_email_enqueued(kind: :account_deletion_confirm)
      assert {:error, {:account_deletion_scheduled, ^at}} = sign_in(account.email)

      assert {:error, :already_scheduled} =
               AccountDeletion.request(
                 account,
                 %{scope: "login", password: @password, confirm_email: account.email},
                 @now
               )
    end

    test "a sole owner of an active business must hand it over first" do
      account = login_with_profiles(["owner"])
      {organization, _owner, _context} = Palee.AnalyticsHelpers.organization_fixture(account)

      assert {:error, {:sole_owner, [name]}} =
               AccountDeletion.request(account, %{scope: "login", password: @password}, @now)

      assert name == organization.name

      co_owner = Palee.TestFixtures.user_fixture()
      Palee.AnalyticsHelpers.add_membership(organization, co_owner, :owner)

      assert {:ok, %{status: :awaiting_confirmation}} =
               AccountDeletion.request(account, %{scope: "login", password: @password}, @now)
    end
  end

  describe "confirm/2 and the grace" do
    test "the link schedules a profile deletion: its sessions die, the other profile stays" do
      account = login_with_profiles(["main", "coach"])
      [main, coach] = Identity.list_profiles(account.login_id)
      :ok = Identity.touch_last_used(account.login_id, main.id)

      {:ok, _} = AccountDeletion.request(main, %{scope: "profile", password: @password}, @now)
      {_message, token} = confirmation_token(account.email)

      assert {:ok, %{status: :scheduled, scope: :profile, scheduled_for: at}} =
               AccountDeletion.confirm(token, @now)

      assert {:error, :invalid_deletion_link} = AccountDeletion.confirm(token, @now)

      assert Identity.find_by_id(main.id).security_version > main.security_version
      assert Identity.find_by_id(coach.id).security_version == coach.security_version

      # The handle opens nothing; the email now opens the other profile.
      assert {:error, {:account_deletion_scheduled, ^at}} = sign_in("@" <> main.handle)
      assert {:ok, %{user: %{id: coach_id}}} = sign_in(account.email)
      assert coach_id == coach.id
      assert {:ok, [%{id: ^coach_id}]} = Palee.Application.AccountProfiles.list(coach)

      assert {:error, {:account_deletion_scheduled, _}} =
               Palee.Application.AccountProfiles.switch(coach, main.id)

      # Nothing happens before the grace is over; then the profile is gone.
      assert AccountDeletion.execute_due(DateTime.add(at, -1, :second)) == 0
      assert AccountDeletion.execute_due(at) == 1
      assert Identity.find_by_id(main.id) == nil
      assert Identity.find_by_id(coach.id)
      assert AccountDeletionStore.for_login(account.login_id) == nil
    end

    test "an expired link schedules nothing" do
      account = login_with_profiles(["main"])
      {:ok, _} = AccountDeletion.request(account, %{scope: "login", password: @password}, @now)
      {_message, token} = confirmation_token(account.email)

      assert {:error, :expired_deletion_link} =
               AccountDeletion.confirm(token, DateTime.add(@now, 25 * 3_600, :second))

      assert %{status: :awaiting_confirmation} = AccountDeletionStore.for_login(account.login_id)
    end

    test "a login deletion removes every profile and the login; the email can sign up again" do
      account = login_with_profiles(["main", "coach"])
      {:ok, _} = AccountDeletion.request(account, %{scope: "login", password: @password}, @now)
      {_message, token} = confirmation_token(account.email)
      {:ok, %{scheduled_for: at}} = AccountDeletion.confirm(token, @now)

      assert {:error, {:account_deletion_scheduled, _}} = sign_in(account.email)

      notice =
        assert_email_enqueued(kind: :security_account_deletion_scheduled, to: account.email)

      assert notice.text =~ "/account-deletion/undo#token="

      assert AccountDeletion.execute_due(at) == 1
      assert Identity.list_profiles(account.login_id) == []
      assert Identity.find_login_by_email(account.email) == nil

      # One notice for the whole login, kept although the login is gone.
      assert %{login_id: nil, user_id: nil} =
               assert_email_enqueued(kind: :security_account_deleted, to: account.email)
    end

    test "a profile a business must keep in its accounts is anonymised, not deleted" do
      account = login_with_profiles(["main"])
      {organization, _owner, _context} = Palee.AnalyticsHelpers.organization_fixture()
      Palee.AnalyticsHelpers.add_membership(organization, account, :member)

      Palee.Repo.query!(
        """
        INSERT INTO memberships (id, user_id, organization_id, user_type_snapshot, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, $2, 'member', now(), now())
        """,
        [Ecto.UUID.dump!(account.id), Ecto.UUID.dump!(organization.id)]
      )

      {:ok, _} = AccountDeletion.request(account, %{scope: "login", password: @password}, @now)
      {_message, token} = confirmation_token(account.email)
      {:ok, %{scheduled_for: at}} = AccountDeletion.confirm(token, @now)
      assert AccountDeletion.execute_due(at) == 1

      kept = Identity.find_by_id(account.id)
      assert kept.handle =~ ~r/^deleted\.[0-9a-f]{10}$/
      assert kept.nickname == "Deleted account"
      assert kept.avatar_url == nil
      assert kept.login_id != account.login_id
      refute kept.email =~ "deleter_"
      assert Identity.find_login_by_email(account.email) == nil

      %{rows: [[count]]} =
        Palee.Repo.query!("SELECT count(*) FROM memberships WHERE user_id = $1", [
          Ecto.UUID.dump!(account.id)
        ])

      assert count == 1
      assert {:error, :invalid_credentials} = sign_in("@" <> kept.handle)
    end
  end

  describe "undo" do
    setup do
      account = login_with_profiles(["main"], verified: false)

      {:ok, %{status: :scheduled}} =
        AccountDeletion.request(
          account,
          %{scope: "login", password: @password, confirm_email: account.email},
          @now
        )

      %{account: account, deletion: AccountDeletionStore.for_login(account.login_id)}
    end

    test "by the emailed link", %{account: account, deletion: deletion} do
      notice =
        assert_email_enqueued(kind: :security_account_deletion_scheduled, to: account.email)

      [_, raw] = Regex.run(~r/undo#token=([A-Za-z0-9_-]{43})/, notice.text)
      assert deletion.status == :scheduled

      assert {:ok, %{status: :none}} = AccountDeletion.cancel_by_link(raw, @now)
      assert {:error, :invalid_deletion_link} = AccountDeletion.cancel_by_link(raw, @now)
      assert {:ok, _tokens} = sign_in(account.email)
      assert AccountDeletion.execute_due(DateTime.add(@now, 8 * 86_400, :second)) == 0
      assert Identity.find_by_id(account.id)
    end

    test "a link of another login undoes nothing", %{deletion: deletion} do
      other = login_with_profiles(["other"])

      {:ok, raw, _token} =
        LinkTokens.issue(:account_deletion_undo, other.login_id,
          metadata: %{"deletion_id" => deletion.id},
          now: @now
        )

      assert {:error, :invalid_deletion_link} = AccountDeletion.cancel_by_link(raw, @now)
      assert AccountDeletionStore.for_login(deletion.login_id)
    end

    test "from the sign-in form with the password", %{account: account} do
      assert {:error, :invalid_credentials} =
               AccountDeletion.cancel_with_credentials(%{
                 identifier: account.email,
                 password: "nope"
               })

      assert AccountDeletionStore.for_login(account.login_id)

      assert {:ok, %{access_token: _, user: %{id: id}}} =
               AccountDeletion.cancel_with_credentials(%{
                 identifier: account.email,
                 password: @password
               })

      assert id == account.id
      assert AccountDeletionStore.for_login(account.login_id) == nil
    end

    test "from a signed-in profile", %{account: account} do
      assert {:ok, %{status: :scheduled}} = AccountDeletion.status(account)
      assert :ok = AccountDeletion.cancel(account)
      assert {:ok, %{status: :none}} = AccountDeletion.status(account)
      assert {:error, :not_found} = AccountDeletion.cancel(account)
    end
  end
end
