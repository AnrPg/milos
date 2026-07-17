defmodule MilosTraining.Application.AdminUserDossierTest do
  use MilosTraining.DataCase, async: true

  import MilosTraining.TestFixtures

  alias MilosTraining.Finance.{ReferralEvent, ReferralReward}
  alias MilosTraining.{Pantheon, Repo}

  alias MilosTraining.Application.{
    GetAdminUserCoachingContext,
    GetAdminUserFinance,
    GetAdminUserIncidents,
    GetAdminUserMessages,
    GetAdminUserPRs,
    GetAdminUserTrainingHistory
  }

  test "member dossier services share a stable user key and safe empty collections" do
    member = user_fixture(%{role: :member})

    assert {:ok, %{user_id: id, available: true}} = GetAdminUserFinance.call(member.id)
    assert id == member.id

    assert {:ok, %{user_id: ^id, executions: [], scores: []}} =
             GetAdminUserTrainingHistory.call(id)

    assert {:ok, %{user_id: ^id, prs: []}} = GetAdminUserPRs.call(id)
    assert {:ok, %{user_id: ^id, incidents: []}} = GetAdminUserIncidents.call(id)
    assert {:ok, %{user_id: ^id, threads: []}} = GetAdminUserMessages.call(id)

    assert {:ok, %{user_id: ^id, available: false, drill_down: nil}} =
             GetAdminUserCoachingContext.call(id)
  end

  test "finance dossier includes package, referral, and referred-member context" do
    member = user_fixture(%{role: :member})
    referred = user_fixture(%{role: :member})

    referral =
      %ReferralEvent{}
      |> ReferralEvent.changeset(%{
        referrer_user_id: member.id,
        referred_user_id: referred.id,
        status: "approved",
        signup_source_snapshot: "referral"
      })
      |> Repo.insert!()

    %ReferralReward{}
    |> ReferralReward.changeset(%{
      referral_event_id: referral.id,
      recipient_user_id: member.id,
      reward_type: "credit",
      reward_value: 1_000,
      status: "approved"
    })
    |> Repo.insert!()

    assert {:ok, %{details: details}} = GetAdminUserFinance.call(member.id)
    assert details.membership == nil
    assert details.package_subscriptions == []

    assert [%{referred_user_id: referred_id, referred_nickname: nickname}] =
             details.referred_members

    assert referred_id == referred.id
    assert nickname == referred.nickname
    assert [%{recipient_user_id: recipient_id}] = details.referral_rewards
    assert recipient_id == member.id
  end

  test "PR dossier includes every prior result with its beaten date" do
    member = user_fixture(%{role: :member})

    assert {:ok, pr} =
             Pantheon.create_pr(member.id, %{
               "name" => "Back squat",
               "current_score" => 100,
               "unit" => "kg",
               "higher_is_better" => true,
               "beaten_on" => ~D[2026-07-01],
               "supporting_metrics" => %{"reps" => 3}
             })

    assert {:ok, _updated} =
             Pantheon.update_pr(pr.id, member.id, %{
               "current_score" => 110,
               "beaten_on" => ~D[2026-07-17]
             })

    assert {:ok, %{prs: [%{history: [history]}]}} = GetAdminUserPRs.call(member.id)
    assert history.beaten_on == "2026-07-01"
    assert Decimal.equal?(Decimal.new(to_string(history.score)), 100)
  end

  test "all focused reads return the same not-found boundary" do
    missing_id = Ecto.UUID.generate()

    for service <- [
          GetAdminUserFinance,
          GetAdminUserTrainingHistory,
          GetAdminUserPRs,
          GetAdminUserIncidents,
          GetAdminUserMessages
        ] do
      assert {:error, :not_found} = service.call(missing_id)
    end

    assert {:error, :not_found} = GetAdminUserCoachingContext.call(missing_id)
  end
end
