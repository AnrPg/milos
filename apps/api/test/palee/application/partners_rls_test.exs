defmodule Palee.Application.PartnersRLSTest do
  @moduledoc """
  ADR-280 at the database level, under the RLS-enforcing runtime role and
  without the application's own filters: Partners rows are personal. A
  profile is its owner's to write, readable by others only while live; a
  swipe is its swiper's (the target sees it only so a crossing like makes
  the match); a match and its conversation are the two people's; a report
  is its reporter's and the Palee team's. A person's blocks are theirs
  alone, and the blocked-ids lookup answers only for the session user.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.TestFixtures

  alias Palee.{Community, Organizations, Partners, Repo}
  alias Palee.Community.UserBlock
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Partners.{Match, Message, Profile, Report, Swipe}

  setup do
    bypass_rls(fn ->
      vendor = user_fixture()
      {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
      %{a: user_fixture(), b: user_fixture(), stranger: user_fixture(), vendor: vendor}
    end)
  end

  defp as(user), do: %{user_id: user.id}

  defp run(user, fun), do: RepoContext.run(as(user), fun)

  defp profile!(user, attrs \\ %{}) do
    {:ok, profile} =
      Partners.create_profile(
        as(user),
        Map.merge(
          %{
            user_id: user.id,
            adult_confirmed_at: DateTime.utc_now(),
            level: "beginner",
            times: ["early"],
            goals: ["strength"]
          },
          attrs
        )
      )

    profile
  end

  defp match!(ctx) do
    now = DateTime.utc_now()
    like = &Partners.mutual?("like", &1)

    {:ok, _} =
      Partners.record_swipe(
        as(ctx.a),
        %{swiper_id: ctx.a.id, target_id: ctx.b.id, direction: "like"},
        like,
        now
      )

    {:ok, %{match: %Match{} = match, new_match: true}} =
      Partners.record_swipe(
        as(ctx.b),
        %{swiper_id: ctx.b.id, target_id: ctx.a.id, direction: "like"},
        like,
        now
      )

    match
  end

  test "a profile is its owner's; others read it only while it is live", ctx do
    profile!(ctx.a)
    paused = profile!(ctx.b, %{paused_at: DateTime.utc_now()})

    assert [%Profile{}] = run(ctx.stranger, fn -> Repo.all(Profile) end)
    assert [%Profile{}, %Profile{}] = run(ctx.b, fn -> Repo.all(Profile) end)
    assert run(ctx.a, fn -> Repo.get(Profile, paused.id) end) == nil

    # Nobody writes someone else's profile.
    assert_raise Postgrex.Error, fn ->
      run(ctx.stranger, fn ->
        Repo.insert!(%Profile{
          user_id: ctx.a.id,
          adult_confirmed_at: DateTime.utc_now(),
          level: "beginner",
          times: ["early"],
          goals: ["strength"]
        })
      end)
    end

    {count, _} =
      run(ctx.stranger, fn ->
        Repo.update_all(Profile, set: [about: "hacked"])
      end)

    assert count == 0

    # A profile needs the 18+ confirmation.
    assert_raise Postgrex.Error, ~r/adult_confirmed_at/, fn ->
      run(ctx.stranger, fn ->
        Repo.insert!(%Profile{
          user_id: ctx.stranger.id,
          level: "beginner",
          times: ["early"],
          goals: ["strength"]
        })
      end)
    end
  end

  test "swipes, matches and messages are the two people's", ctx do
    profile!(ctx.a)
    profile!(ctx.b)
    match = match!(ctx)

    assert {:ok, %Message{}} =
             Partners.insert_message(
               as(ctx.a),
               %{match_id: match.id, author_id: ctx.a.id, kind: "text", body: "hi"},
               DateTime.utc_now()
             )

    for user <- [ctx.a, ctx.b] do
      assert [%Match{}] = run(user, fn -> Repo.all(Match) end)
      assert [%Message{}] = run(user, fn -> Repo.all(Message) end)
    end

    assert run(ctx.stranger, fn -> Repo.all(Swipe) end) == []
    assert run(ctx.stranger, fn -> Repo.all(Match) end) == []
    assert run(ctx.stranger, fn -> Repo.all(Message) end) == []

    # A stranger neither writes into the pair's conversation nor swipes as someone else.
    assert_raise Postgrex.Error, fn ->
      run(ctx.stranger, fn ->
        Repo.insert!(%Message{match_id: match.id, author_id: ctx.stranger.id, body: "hey"})
      end)
    end

    assert_raise Postgrex.Error, fn ->
      run(ctx.stranger, fn ->
        Repo.insert!(%Swipe{swiper_id: ctx.a.id, target_id: ctx.stranger.id, direction: "like"})
      end)
    end

    # One active match per pair.
    assert_raise Ecto.ConstraintError, ~r/partner_matches_active_pair_index/, fn ->
      run(ctx.a, fn ->
        {a, b} = Partners.pair(ctx.a.id, ctx.b.id)
        Repo.insert!(%Match{user_a_id: a, user_b_id: b, matched_at: DateTime.utc_now()})
      end)
    end

    # Once ended, nobody writes in it any more.
    {:ok, changes} = Partners.end_changes(match, "unmatched", ctx.a.id, DateTime.utc_now())
    {:ok, _ended} = Partners.update_match(as(ctx.a), match, changes)

    assert_raise Postgrex.Error, fn ->
      run(ctx.b, fn ->
        Repo.insert!(%Message{match_id: match.id, author_id: ctx.b.id, body: "still there?"})
      end)
    end
  end

  test "a report is its reporter's and the Palee team's", ctx do
    assert {:ok, %Report{} = report} =
             Partners.insert_report(as(ctx.a), %{
               reporter_id: ctx.a.id,
               target_id: ctx.b.id,
               reason: "fake",
               note: nil
             })

    assert {:ok, :already_reported} =
             Partners.insert_report(as(ctx.a), %{
               reporter_id: ctx.a.id,
               target_id: ctx.b.id,
               reason: "other",
               note: nil
             })

    assert [%Report{}] = run(ctx.a, fn -> Repo.all(Report) end)
    assert run(ctx.b, fn -> Repo.all(Report) end) == []
    assert run(ctx.stranger, fn -> Repo.all(Report) end) == []
    assert [%Report{}] = Partners.list_reports(as(ctx.vendor), "open")

    # The reporter can't decide their own report; the Palee team can.
    assert_raise Ecto.StaleEntryError, fn ->
      Partners.decide_reports(as(ctx.a), ctx.b.id, %{
        status: "actioned",
        decided_at: DateTime.utc_now()
      })
    end

    assert [%Report{status: "dismissed"}] =
             Partners.decide_reports(as(ctx.vendor), ctx.b.id, %{
               status: "dismissed",
               decided_by_id: ctx.vendor.id,
               decided_at: DateTime.utc_now()
             })

    assert %Report{status: "dismissed"} = Partners.get_report(as(ctx.a), report.id)

    # Nobody files a report in someone else's name.
    assert_raise Postgrex.Error, fn ->
      run(ctx.stranger, fn ->
        Repo.insert!(%Report{reporter_id: ctx.a.id, target_id: ctx.b.id, reason: "fake"})
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
