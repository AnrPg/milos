defmodule PaleeWeb.ChallengeControllerTest do
  @moduledoc """
  TD-092: a member's challenge leaderboard and opt-in run in the gym's tenant
  scope. Challenges and opt-ins are tenant rows, so the former unscoped
  `/api/challenges/...` routes answered 404 for every challenge under the
  production runtime role.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Gamification, Organizations}

  setup do
    owner = user_fixture()
    member = user_fixture()
    {:ok, gym} = Organizations.create_organization(%{name: "Challenge Gym"})

    for {user, role} <- [{owner, :owner}, {member, :member}] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: gym.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, owner_ctx} = Organizations.resolve_tenant_context(owner, gym.slug)

    {:ok, challenge} =
      Gamification.with_tenant_context(owner_ctx, fn ->
        Gamification.create_seasonal_challenge(owner.id, %{
          title: "October push",
          description: "Three workouts",
          criteria_type: "workout_count",
          criteria_value: %{count: 3},
          badge_key: "challenge_october_push",
          badge_label: "October push",
          starts_at: Date.utc_today(),
          ends_at: Date.add(Date.utc_today(), 14)
        })
      end)

    %{gym: gym, member: member, challenge: challenge}
  end

  test "a member opts in, sees the challenge leaderboard and opts out", ctx do
    base = "/api/org/#{ctx.gym.slug}/challenges/#{ctx.challenge.id}"

    assert %{"opted_in" => true} =
             build_conn()
             |> put_bearer_token(ctx.member)
             |> post("#{base}/opt_in")
             |> json_response(200)

    assert Gamification.with_tenant_context(%{organization_id: ctx.gym.id}, fn ->
             Gamification.challenge_leaderboard_opted_in?(ctx.member.id, ctx.challenge.id)
           end)

    assert %{"challenge_id" => challenge_id, "participants" => participants} =
             build_conn()
             |> put_bearer_token(ctx.member)
             |> get("#{base}/leaderboard")
             |> json_response(200)

    assert challenge_id == ctx.challenge.id
    assert is_list(participants)

    assert %{"opted_in" => false} =
             build_conn()
             |> put_bearer_token(ctx.member)
             |> delete("#{base}/opt_in")
             |> json_response(200)

    refute Gamification.with_tenant_context(%{organization_id: ctx.gym.id}, fn ->
             Gamification.challenge_leaderboard_opted_in?(ctx.member.id, ctx.challenge.id)
           end)
  end

  test "a challenge of another gym is not found", ctx do
    {:ok, other} = Organizations.create_organization(%{name: "Other Challenge Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: other.id,
        user_id: ctx.member.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    assert build_conn()
           |> put_bearer_token(ctx.member)
           |> get("/api/org/#{other.slug}/challenges/#{ctx.challenge.id}/leaderboard")
           |> json_response(404)
  end
end
