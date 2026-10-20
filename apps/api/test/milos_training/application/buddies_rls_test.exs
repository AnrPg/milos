defmodule MilosTraining.Application.BuddiesRLSTest do
  @moduledoc """
  ADR-160 at the database level, under the RLS-enforcing runtime role and
  without the application's own filters: a link is visible to its two
  people only; a support request to its sender, and to a buddy only once
  delivered and not taken back; settings and summary grants to their
  owner; quiet hours and a shared phone only across an active link; the
  eligibility lookup answers only for the session user.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import MilosTraining.TestFixtures

  alias MilosTraining.{Buddies, Organizations, Repo}
  alias MilosTraining.Buddies.{Link, SupportRequest}
  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  setup do
    bypass_rls(fn ->
      {:ok, gym} = Organizations.create_organization(%{name: "RLS Buddy Box"})
      member = user_fixture()
      buddy = user_fixture()
      stranger = user_fixture()

      for user <- [member, buddy] do
        {:ok, _} =
          Organizations.add_membership(%{
            organization_id: gym.id,
            user_id: user.id,
            role: :member,
            status: :active,
            joined_at: DateTime.utc_now()
          })
      end

      %{member: member, buddy: buddy, stranger: stranger}
    end)
  end

  defp ctx(user), do: %{user_id: user.id}
  defp now, do: DateTime.utc_now()

  defp active_link!(ctx) do
    {:ok, link} =
      Buddies.create_link(
        ctx(ctx.member),
        %{
          user_id: ctx.member.id,
          buddy_user_id: ctx.buddy.id,
          status: "pending",
          expires_at: Buddies.invite_expires_at(now())
        },
        fn _ -> :ok end
      )

    {:ok, link} =
      Buddies.update_link(ctx(ctx.buddy), link, %{status: "active", started_at: now()})

    link
  end

  defp request!(ctx) do
    {:ok, request} =
      Buddies.create_request(
        ctx(ctx.member),
        %{user_id: ctx.member.id, message: "hard", source: "quick", inserted_at: now()},
        [%{buddy_user_id: ctx.buddy.id, silent: false}],
        fn _ -> :ok end,
        DateTime.add(now(), -3600, :second)
      )

    request
  end

  defp visible(user, query),
    do: RepoContext.run(ctx(user), fn -> Repo.all(query) end)

  test "a link is visible to its two people only", ctx do
    link = active_link!(ctx)

    assert [%{id: id}] = visible(ctx.member, Link)
    assert id == link.id
    assert [%{id: ^id}] = visible(ctx.buddy, Link)
    assert visible(ctx.stranger, Link) == []

    # Nobody writes a link between two other people.
    assert_raise Postgrex.Error, fn ->
      RepoContext.run(ctx(ctx.stranger), fn ->
        Repo.insert!(%Link{user_id: ctx.member.id, buddy_user_id: ctx.buddy.id, status: "ended"})
      end)
    end
  end

  test "a buddy reads a request only once delivered and not taken back", ctx do
    active_link!(ctx)
    request = request!(ctx)

    assert [_] = visible(ctx.member, SupportRequest)
    assert visible(ctx.buddy, SupportRequest) == []
    assert visible(ctx.stranger, SupportRequest) == []

    assert 1 = Buddies.mark_delivered(ctx(ctx.member), request.id, now())
    assert [%{message: "hard"}] = visible(ctx.buddy, SupportRequest)
    assert visible(ctx.stranger, SupportRequest) == []

    # The buddy cannot change the request itself.
    assert 0 = Buddies.undo_request(ctx(ctx.buddy), request.id, now())

    second = request!(ctx)
    assert 1 = Buddies.undo_request(ctx(ctx.member), second.id, now())
    assert 0 = Buddies.mark_delivered(ctx(ctx.member), second.id, now())
    assert [%{id: id}] = visible(ctx.buddy, SupportRequest)
    assert id == request.id
  end

  test "settings and summary grants are the owner's; quiet hours and phone cross only a link",
       ctx do
    {:ok, _} =
      Buddies.put_settings(ctx(ctx.buddy), ctx.buddy.id, %{
        quiet_from: ~T[23:00:00],
        quiet_to: ~T[07:00:00],
        tz: "Europe/Athens"
      })

    {:ok, _} =
      Buddies.put_settings(ctx(ctx.member), ctx.member.id, %{
        share_phone: true,
        phone: "+30 690 123 4567",
        tz: "Europe/Athens"
      })

    {:ok, _} = Buddies.grant_summary(ctx(ctx.member), ctx.member.id, "wellness", now())

    assert visible(ctx.stranger, MilosTraining.Buddies.Settings) == []
    assert [%{user_id: own}] = visible(ctx.member, MilosTraining.Buddies.Settings)
    assert own == ctx.member.id
    assert visible(ctx.buddy, MilosTraining.Buddies.SummaryGrant) == []

    # Before they are buddies, nothing crosses.
    assert Buddies.quiet_hours(ctx(ctx.member), ctx.buddy.id) == nil
    assert Buddies.shared_phone(ctx(ctx.buddy), ctx.member.id) == nil

    active_link!(ctx)

    assert %{quiet_from: from} = Buddies.quiet_hours(ctx(ctx.member), ctx.buddy.id)
    assert Time.compare(from, ~T[23:00:00]) == :eq
    assert Buddies.shared_phone(ctx(ctx.buddy), ctx.member.id) == "+30 690 123 4567"
    # The phone goes to the member's buddies, not the other way round.
    assert Buddies.shared_phone(ctx(ctx.member), ctx.buddy.id) == nil
    assert Buddies.shared_phone(ctx(ctx.stranger), ctx.member.id) == nil
  end

  test "eligibility and candidates answer for the session user only", ctx do
    assert Buddies.relation(ctx(ctx.member), ctx.buddy.id) == "club"
    assert Buddies.relation(ctx(ctx.member), ctx.stranger.id) == nil
    assert Buddies.relation(ctx(ctx.member), ctx.member.id) == nil

    found = Buddies.candidates(ctx(ctx.member), String.slice(ctx.buddy.nickname, 0, 6), 20)
    assert Enum.any?(found, &(&1.user_id == ctx.buddy.id))
    refute Enum.any?(found, &(&1.user_id == ctx.stranger.id))
    assert Buddies.candidates(ctx(ctx.stranger), "user", 20) == []
  end

  test "an invite link is claimed once, never by its author", ctx do
    token = Buddies.generate_invite_token()
    digest = Buddies.invite_token_digest(token)

    {:ok, link} =
      Buddies.create_link(
        ctx(ctx.member),
        %{
          user_id: ctx.member.id,
          invite_token_hash: digest,
          status: "pending",
          expires_at: Buddies.invite_expires_at(now())
        },
        fn _ -> :ok end
      )

    assert %{status: "pending"} = Buddies.invite_preview(digest, now())
    assert Buddies.claim_invite(ctx(ctx.member), digest, now()) == nil
    assert visible(ctx.stranger, Link) == []
    assert Buddies.claim_invite(ctx(ctx.stranger), digest, now()) == link.id
    assert [%{status: "active"}] = visible(ctx.stranger, Link)
    assert Buddies.claim_invite(ctx(ctx.buddy), digest, now()) == nil
    assert %{status: "unavailable"} = Buddies.invite_preview(digest, now())

    expired = Buddies.generate_invite_token()

    {:ok, _} =
      Buddies.create_link(
        ctx(ctx.member),
        %{
          user_id: ctx.member.id,
          invite_token_hash: Buddies.invite_token_digest(expired),
          status: "pending",
          expires_at: DateTime.add(now(), -60, :second)
        },
        fn _ -> :ok end
      )

    assert Buddies.claim_invite(ctx(ctx.buddy), Buddies.invite_token_digest(expired), now()) ==
             nil

    assert %{status: "expired"} =
             Buddies.invite_preview(Buddies.invite_token_digest(expired), now())
  end
end
