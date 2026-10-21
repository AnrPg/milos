defmodule Palee.Application.CheckInRLSTest do
  @moduledoc """
  ADR-140 §2 Πώς νιώθω under real Row Level Security: immutable, timestamped
  submissions with per-question answers; the owner reads them all; a coach of
  the provenance gym reads them (answers included) only while the rung
  reaches the coach.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.TestFixtures

  alias Palee.Application.{DeleteMyCheckIn, ListMyCheckIns, SubmitCheckIn}
  alias Palee.Identity.UserContext
  alias Palee.{Journal, Organizations, Wellbeing}

  setup do
    fixtures =
      bypass_rls(fn ->
        {:ok, gym} = Organizations.create_organization(%{name: "Check-in Gym"})
        coach = user_fixture()
        member = user_fixture()
        other = user_fixture()
        add!(gym, coach, :coach)
        add!(gym, member, :member)
        %{gym: gym, coach: coach, member: member, other: other}
      end)

    Map.merge(fixtures, %{
      member_ctx: UserContext.new(fixtures.member),
      other_ctx: UserContext.new(fixtures.other),
      coach_ctx: tenant!(fixtures.coach, fixtures.gym)
    })
  end

  test "a submission stores each answer, in catalog order, privately by default", ctx do
    assert {:ok, check_in} =
             SubmitCheckIn.call(ctx.member_ctx, %{
               "organization_slug" => ctx.gym.slug,
               "recorded_tz" => "Europe/Athens",
               "answers" => [
                 %{"question_key" => "stress", "value" => 2, "note" => "  deadline  "},
                 %{"question_key" => "sleep", "value" => 4, "note" => " "}
               ]
             })

    assert check_in.organization_id == ctx.gym.id
    assert check_in.journal_visibility == "private"
    assert check_in.recorded_tz == "Europe/Athens"

    assert [
             %{question_key: "sleep", value: 4, note: nil},
             %{question_key: "stress", value: 2, note: "deadline"}
           ] = check_in.answers
  end

  test "invalid submissions are refused", ctx do
    for answers <- [
          [],
          [%{"question_key" => "hunger", "value" => 2}],
          [%{"question_key" => "mood", "value" => 5}],
          [%{"question_key" => "mood", "value" => 0}],
          [%{"question_key" => "mood", "value" => 2}, %{"question_key" => "mood", "value" => 3}],
          [%{"question_key" => "mood", "value" => 2, "note" => String.duplicate("a", 1001)}]
        ] do
      assert {:error, %Ecto.Changeset{}} =
               SubmitCheckIn.call(ctx.member_ctx, %{"answers" => answers}),
             "expected #{inspect(answers)} to be refused"
    end

    {:ok, foreign} = bypass_rls(fn -> Organizations.create_organization(%{name: "Elsewhere"}) end)

    assert {:error, :check_in_organization_unavailable} =
             SubmitCheckIn.call(ctx.member_ctx, %{
               "organization_slug" => foreign.slug,
               "answers" => [%{"question_key" => "mood", "value" => 3}]
             })
  end

  test "many submissions a day form a timeline, oldest first; deleting removes one", ctx do
    morning = ~U[2026-10-16 07:00:00.000000Z]
    noon = ~U[2026-10-16 12:00:00.000000Z]

    {:ok, first} =
      SubmitCheckIn.call(ctx.member_ctx, %{"answers" => [answer("energy", 1)]}, morning)

    {:ok, second} =
      SubmitCheckIn.call(ctx.member_ctx, %{"answers" => [answer("energy", 3)]}, noon)

    {:ok, _other} =
      SubmitCheckIn.call(ctx.other_ctx, %{"answers" => [answer("energy", 4)]}, noon)

    window = %{"from" => "2026-10-16T00:00:00Z", "to" => "2026-10-17T00:00:00Z"}

    assert {:ok, %{questions: questions, check_ins: check_ins}} =
             ListMyCheckIns.call(ctx.member_ctx, window)

    assert Enum.map(questions, & &1.key) == ~w(sleep energy mood stress body)
    assert Enum.map(check_ins, & &1.id) == [first.id, second.id]
    assert Enum.map(check_ins, &hd(&1.answers).value) == [1, 3]

    assert {:error, :not_found} = DeleteMyCheckIn.call(ctx.other_ctx, first.id)
    assert :ok = DeleteMyCheckIn.call(ctx.member_ctx, first.id)

    assert {:ok, %{check_ins: [%{id: remaining}]}} = ListMyCheckIns.call(ctx.member_ctx, window)
    assert remaining == second.id

    assert {:error, :invalid_range} =
             ListMyCheckIns.call(ctx.member_ctx, %{"from" => window["to"], "to" => window["from"]})
  end

  test "the coach reads gym check-ins and their answers only on a rung that reaches them", ctx do
    {:ok, private} =
      SubmitCheckIn.call(ctx.member_ctx, %{
        "organization_slug" => ctx.gym.slug,
        "answers" => [answer("mood", 2)]
      })

    :ok =
      Journal.with_context(ctx.member_ctx, fn ->
        Journal.put_visibility_default(ctx.member.id, "check_in", "coach_can_view")
      end)

    {:ok, shared} =
      SubmitCheckIn.call(ctx.member_ctx, %{
        "organization_slug" => ctx.gym.slug,
        "answers" => [answer("body", 3, "tight hamstrings")]
      })

    {:ok, personal} = SubmitCheckIn.call(ctx.member_ctx, %{"answers" => [answer("mood", 4)]})

    assert private.journal_visibility == "private"
    assert shared.journal_visibility == "coach_can_view"
    assert personal.journal_visibility == "private"

    seen =
      Wellbeing.with_tenant_context(ctx.coach_ctx, fn ->
        Wellbeing.list_coach_visible_check_ins(ctx.member.id, ctx.gym.id)
      end)

    assert [%{id: shared_id, answers: [%{question_key: "body", note: "tight hamstrings"}]}] = seen
    assert shared_id == shared.id

    # The answers table admits the coach only through a readable parent.
    answer_owners =
      Wellbeing.with_tenant_context(ctx.coach_ctx, fn ->
        Palee.Repo.all(Palee.Wellbeing.CheckInAnswer)
        |> Enum.map(& &1.check_in_id)
      end)

    assert answer_owners == [shared.id]
  end

  defp answer(key, value, note \\ nil),
    do: %{"question_key" => key, "value" => value, "note" => note}

  defp add!(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end

  defp tenant!(user, organization) do
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end
end
