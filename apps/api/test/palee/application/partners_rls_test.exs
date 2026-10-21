defmodule Palee.Application.PartnersRLSTest do
  @moduledoc """
  ADR-169 at the database level, under the RLS-enforcing runtime role and
  without the application's own filters: Partners rows belong to the club's
  gym and never show in another gym's session; a person's blocks are
  theirs alone, and the blocked-ids lookup answers only for the session
  user.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.TestFixtures

  alias Palee.{Community, Organizations, Partners, Repo}
  alias Palee.Community.UserBlock
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Partners.{Match, Profile, Swipe}

  setup do
    bypass_rls(fn ->
      {:ok, gym} = Organizations.create_organization(%{name: "RLS Partners Box"})
      {:ok, other_gym} = Organizations.create_organization(%{name: "RLS Other Box"})
      a = user_fixture()
      b = user_fixture()
      stranger = user_fixture()

      for user <- [a, b] do
        {:ok, _} =
          Organizations.add_membership(%{
            organization_id: gym.id,
            user_id: user.id,
            role: :member,
            status: :active,
            joined_at: DateTime.utc_now()
          })
      end

      {:ok, club} = Community.provision_gym_club(%{organization_id: gym.id, user_id: a.id})
      %{gym: gym, other_gym: other_gym, club: club, a: a, b: b, stranger: stranger}
    end)
  end

  defp in_gym(gym, user), do: %{organization_id: gym.id, user_id: user.id}

  defp profile!(ctx, user) do
    {:ok, profile} =
      Partners.create_profile(in_gym(ctx.gym, user), %{
        club_id: ctx.club.id,
        user_id: user.id,
        level: "beginner",
        times: ["early"],
        goals: ["strength"]
      })

    profile
  end

  test "profiles, swipes and matches stay in the club's gym", ctx do
    profile!(ctx, ctx.a)
    profile!(ctx, ctx.b)
    now = DateTime.utc_now()
    like = &Partners.mutual?("like", &1)

    {:ok, _} =
      Partners.record_swipe(
        in_gym(ctx.gym, ctx.a),
        %{club_id: ctx.club.id, swiper_id: ctx.a.id, target_id: ctx.b.id, direction: "like"},
        like,
        now
      )

    {:ok, %{match: %Match{}, new_match: true}} =
      Partners.record_swipe(
        in_gym(ctx.gym, ctx.b),
        %{club_id: ctx.club.id, swiper_id: ctx.b.id, target_id: ctx.a.id, direction: "like"},
        like,
        now
      )

    in_gym = fn query -> RepoContext.run(in_gym(ctx.gym, ctx.a), fn -> Repo.all(query) end) end

    elsewhere = fn query ->
      RepoContext.run(in_gym(ctx.other_gym, ctx.a), fn -> Repo.all(query) end)
    end

    personal = fn query -> RepoContext.run(%{user_id: ctx.a.id}, fn -> Repo.all(query) end) end

    for schema <- [Profile, Swipe, Match] do
      assert in_gym.(schema) != []
      assert elsewhere.(schema) == []
      assert personal.(schema) == []
    end

    # Nobody writes a gym's Partners row from another gym: the session's gym
    # is stamped on the row and the club's gym must match it.
    assert_raise Ecto.ConstraintError, ~r/partner_swipes_club_gym_fkey/, fn ->
      RepoContext.run(in_gym(ctx.other_gym, ctx.stranger), fn ->
        Repo.insert!(%Swipe{
          organization_id: ctx.gym.id,
          club_id: ctx.club.id,
          swiper_id: ctx.stranger.id,
          target_id: ctx.a.id,
          direction: "like"
        })
      end)
    end
  end

  test "blocks are the blocker's; the lookup answers for the session user only", ctx do
    assert {:ok, _} = Community.block_user(%{user_id: ctx.a.id}, ctx.b.id)

    mine = RepoContext.run(%{user_id: ctx.a.id}, fn -> Repo.all(UserBlock) end)
    assert [%{blocked_user_id: blocked}] = mine
    assert blocked == ctx.b.id
    assert RepoContext.run(%{user_id: ctx.b.id}, fn -> Repo.all(UserBlock) end) == []

    # Both sides learn they are apart; nobody else learns anything.
    assert Community.blocked_user_ids(%{user_id: ctx.a.id}) == [ctx.b.id]
    assert Community.blocked_user_ids(%{user_id: ctx.b.id}) == [ctx.a.id]
    assert Community.blocked_user_ids(%{user_id: ctx.stranger.id}) == []

    # Nobody blocks on someone else's behalf.
    assert_raise Postgrex.Error, fn ->
      RepoContext.run(%{user_id: ctx.stranger.id}, fn ->
        Repo.insert!(%UserBlock{user_id: ctx.a.id, blocked_user_id: ctx.stranger.id})
      end)
    end
  end
end
