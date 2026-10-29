defmodule Palee.Application.ReleasedEmailReservationTest do
  @moduledoc """
  ADR-211: after an ADR-207 email change the old address stays held for its
  login for 7 days. Sign-up and email changes to it by anyone else answer as
  usual and create nothing; only that login's revert takes it back.
  """
  use Palee.DataCase, async: false
  use Palee.EmailCase

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Application.{EmailChange, RegisterUser}
  alias Palee.Identity
  alias Palee.Identity.{Login, PendingEmailChange}
  alias Palee.Organizations.Domain.InvitationEmail
  alias Palee.Repo

  @password "S3cur3P@ss!42"

  defp token_from(message, path) do
    [_, token] = Regex.run(~r{#{path}#token=([A-Za-z0-9_-]+)}, message.text)
    token
  end

  # The owner moves from its address to new@box.test; returns the revert link.
  defp change_away!(user, now \\ DateTime.utc_now()) do
    {:ok, _status} = EmailChange.request(user, "new@box.test", @password, now)
    message = assert_email_enqueued(kind: :email_change_confirm, to: "new@box.test")
    {:ok, _} = EmailChange.confirm(token_from(message, "/confirm-email-change"), now)
    notice = assert_email_enqueued(kind: :security_email_changed, to: user.email)
    token_from(notice, "/revert-email-change")
  end

  defp sign_up(email) do
    unique = System.unique_integer([:positive])

    RegisterUser.call(%{
      "handle" => "taker#{unique}",
      "password" => "An0ther-P@ss!",
      "role" => "member",
      "email" => email,
      "age_confirmed" => true
    })
  end

  setup do
    %{owner: user_fixture()}
  end

  test "only a digest of the released address is stored", %{owner: owner} do
    change_away!(owner)

    [row] =
      Repo.all(
        from r in "released_email_reservations",
          select: %{digest: r.address_digest, login_id: r.login_id, until: r.reserved_until}
      )

    assert row.digest == InvitationEmail.digest(owner.email)
    assert Ecto.UUID.cast!(row.login_id) == owner.login_id
    assert NaiveDateTime.diff(row.until, NaiveDateTime.utc_now()) > 6 * 24 * 3600
    refute inspect(row) =~ owner.email
  end

  test "a sign-up with the released address answers neutrally and creates nothing",
       %{owner: owner} do
    change_away!(owner)
    logins = Repo.aggregate(Login, :count)

    assert {:confirmation_sent, email} = sign_up(" " <> String.upcase(owner.email))
    assert email == owner.email
    assert Repo.aggregate(Login, :count) == logins
    refute Identity.find_login_by_email(owner.email)
    refute_email_enqueued(kind: :signup_attempt_existing)
    refute_email_enqueued(kind: :verify_email, to: owner.email)

    # A bad field is still refused, as for any sign-up.
    assert {:error, %Ecto.Changeset{}} =
             RegisterUser.call(%{
               "handle" => "x",
               "password" => "short",
               "email" => owner.email,
               "age_confirmed" => true
             })
  end

  test "the hold ends after 7 days", %{owner: owner} do
    change_away!(owner)
    later = DateTime.add(DateTime.utc_now(), 7 * 24 * 3600 + 60, :second)
    refute Identity.email_reserved_for_other?(owner.email, nil, later)
    assert Identity.email_reserved_for_other?(owner.email)
  end

  test "another login's change to it answers as usual and records nothing", %{owner: owner} do
    change_away!(owner)
    other = user_fixture()

    assert {:ok, status} = EmailChange.request(other, owner.email, @password)
    assert status.pending.email == owner.email
    refute_email_enqueued(kind: :email_change_confirm, to: owner.email)
    assert Repo.aggregate(where(PendingEmailChange, login_id: ^other.login_id), :count) == 0
  end

  test "a change requested before the release cannot confirm onto it", %{owner: owner} do
    other = user_fixture()
    {:ok, _} = EmailChange.request(other, owner.email, @password)
    message = assert_email_enqueued(kind: :email_change_confirm, to: owner.email)

    change_away!(owner)

    assert {:error, :email_unavailable} =
             EmailChange.confirm(token_from(message, "/confirm-email-change"))

    assert Repo.get!(Login, other.login_id).email == other.email
  end

  test "the owner's revert takes it back and ends the hold", %{owner: owner} do
    revert = change_away!(owner)
    assert {:ok, %{email: email}} = EmailChange.revert(revert)
    assert email == owner.email
    refute Identity.email_reserved_for_other?(owner.email)
    assert Repo.aggregate("released_email_reservations", :count) == 0
  end
end
