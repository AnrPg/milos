defmodule Palee.Application.PasswordRecoveryTest do
  use Palee.DataCase, async: false

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0, add_membership: 3]

  alias Palee.Application.{LoginUser, PasswordRecovery}
  alias Palee.Identity.PasswordResetLogEntry
  alias Palee.Organizations.Vendor
  alias Palee.TestFixtures

  setup do
    person = TestFixtures.user_fixture(%{nickname: "forgetful", email: "forgetful@example.com"})
    vendor = TestFixtures.user_fixture()
    {:ok, _vendor} = Repo.insert(Vendor.changeset(%{user_id: vendor.id}))

    {organization, owner, _context} = organization_fixture()
    add_membership(organization, person, :member)
    desk = TestFixtures.user_fixture()
    add_membership(organization, desk, :front_desk)
    coach_in_box = TestFixtures.user_fixture()
    add_membership(organization, coach_in_box, :coach)

    %{person: person, vendor: vendor, owner: owner, desk: desk, outsider: coach_in_box}
  end

  defp request_id(viewer) do
    [%{id: id}] = PasswordRecovery.inbox(viewer)
    id
  end

  test "a request reaches the vendor and the box's owner and front desk, not other staff", ctx do
    assert :ok = PasswordRecovery.request("@Forgetful")

    for viewer <- [ctx.vendor, ctx.owner, ctx.desk] do
      assert [%{state: :open, person: %{handle: "forgetful", email: "forgetful@example.com"}}] =
               PasswordRecovery.inbox(viewer)
    end

    assert PasswordRecovery.inbox(ctx.outsider) == []
    assert PasswordRecovery.inbox(ctx.person) == []

    # One open request per login; unknown accounts get the same answer.
    assert :ok = PasswordRecovery.request("forgetful@example.com")
    assert :ok = PasswordRecovery.request("nobody@example.com")
    assert length(PasswordRecovery.inbox(ctx.vendor)) == 1
  end

  test "the first opener holds the request; the vendor can take over", ctx do
    :ok = PasswordRecovery.request("forgetful")
    id = request_id(ctx.desk)

    assert {:ok, %{state: :mine}} = PasswordRecovery.claim(ctx.desk, id)
    assert [%{state: :taken, claimed_by: %{handle: _}}] = PasswordRecovery.inbox(ctx.owner)
    assert {:error, :claimed_by_other} = PasswordRecovery.claim(ctx.owner, id)
    assert {:error, :claimed_by_other} = PasswordRecovery.issue_link(ctx.owner, id)

    assert {:ok, %{state: :mine}} = PasswordRecovery.claim(ctx.vendor, id)
  end

  test "an idle claim lapses after 30 minutes", ctx do
    :ok = PasswordRecovery.request("forgetful")
    id = request_id(ctx.desk)
    now = DateTime.utc_now()

    {:ok, _entry} = PasswordRecovery.claim(ctx.desk, id, now)
    later = DateTime.add(now, 31 * 60, :second)
    assert {:ok, %{state: :mine}} = PasswordRecovery.claim(ctx.owner, id, later)
  end

  test "a reset link sets a new password once and signs the person out", ctx do
    :ok = PasswordRecovery.request("forgetful")
    id = request_id(ctx.owner)

    assert {:ok, %{token: token, email: "forgetful@example.com"}} =
             PasswordRecovery.issue_link(ctx.owner, id)

    assert [%{state: :link_sent}] = PasswordRecovery.inbox(ctx.desk)
    assert {:error, :weak_password} = PasswordRecovery.complete(token, "abc")
    assert :ok = PasswordRecovery.complete(token, "new pass")
    assert {:error, :invalid_reset_link} = PasswordRecovery.complete(token, "other pass")

    assert {:ok, _session} = LoginUser.call(%{identifier: "forgetful", password: "new pass"})
    assert PasswordRecovery.inbox(ctx.vendor) == []

    events = Repo.all(PasswordResetLogEntry) |> Enum.map(& &1.event)
    assert "requested" in events and "link_issued" in events and "completed" in events
  end

  test "an expired link shows as expired, can be re-sent or dismissed", ctx do
    :ok = PasswordRecovery.request("forgetful")
    id = request_id(ctx.owner)
    now = DateTime.utc_now()
    {:ok, %{token: token}} = PasswordRecovery.issue_link(ctx.owner, id, now)

    later = DateTime.add(now, 25 * 3600, :second)
    assert [%{state: :expired}] = PasswordRecovery.inbox(ctx.desk, later)
    assert {:error, :expired_reset_link} = PasswordRecovery.complete(token, "new pass", later)

    assert {:ok, %{token: _new}} = PasswordRecovery.issue_link(ctx.desk, id, later)
    assert :ok = PasswordRecovery.close(ctx.desk, id, :dismissed, later)
    assert PasswordRecovery.inbox(ctx.vendor) == []
  end

  test "a handler can hide a request from their own list only", ctx do
    :ok = PasswordRecovery.request("forgetful")
    id = request_id(ctx.owner)

    assert :ok = PasswordRecovery.hide(ctx.owner, id)
    assert PasswordRecovery.inbox(ctx.owner) == []
    assert [_request] = PasswordRecovery.inbox(ctx.desk)
    assert {:error, :not_found} = PasswordRecovery.hide(ctx.outsider, id)
  end

  test "a coach of the person handles the request too", ctx do
    {organization, _owner, _context} = organization_fixture()
    coach = TestFixtures.user_fixture()
    add_membership(organization, coach, :coach)

    Repo.query!(
      """
      INSERT INTO coaching_relationships (id, organization_id, coach_user_id, client_user_id, origin, started_at, inserted_at, updated_at)
      VALUES (gen_random_uuid(), $1, $2, $3, 'assigned', now(), now(), now())
      """,
      [
        Ecto.UUID.dump!(organization.id),
        Ecto.UUID.dump!(coach.id),
        Ecto.UUID.dump!(ctx.person.id)
      ]
    )

    :ok = PasswordRecovery.request("forgetful")
    assert [%{sources: ["coach"]}] = PasswordRecovery.inbox(coach)
  end

  test "recovery codes reset the password without help, once each", ctx do
    assert {:error, :invalid_current_password} =
             PasswordRecovery.generate_codes(ctx.person, "wrong")

    {:ok, [code | _rest] = codes} = PasswordRecovery.generate_codes(ctx.person, "S3cur3P@ss!42")
    assert length(codes) == 10
    assert %{total: 10, unused: 10} = PasswordRecovery.codes_status(ctx.person)

    assert {:error, :invalid_recovery_code} =
             PasswordRecovery.redeem_code("forgetful", "zzzzz-zzzzz", "new pass")

    assert :ok = PasswordRecovery.redeem_code("forgetful", String.upcase(code), "new pass")

    assert {:error, :invalid_recovery_code} =
             PasswordRecovery.redeem_code("forgetful", code, "x pass")

    assert %{unused: 9} = PasswordRecovery.codes_status(ctx.person)
    assert {:ok, _session} = LoginUser.call(%{identifier: "forgetful", password: "new pass"})
  end
end
