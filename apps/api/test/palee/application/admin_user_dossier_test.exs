defmodule Palee.Application.AdminUserDossierTest do
  use Palee.DataCase, async: true

  import Palee.TestFixtures

  alias Palee.Finance
  alias Palee.Finance.{ReferralEvent, ReferralReward}
  alias Palee.{Organizations, Pantheon, Repo}

  alias Palee.Application.{
    GetAdminUserCoachingContext,
    GetAdminUserFinance,
    GetAdminUserIncidents,
    GetAdminUserMessages,
    GetAdminUserPRs,
    GetAdminUserTrainingHistory
  }

  test "member dossier services share a stable user key and safe empty collections" do
    member = user_fixture(%{role: :member})
    tenant_context = legacy_tenant_context(member)

    assert {:ok, %{user_id: id, available: true}} =
             GetAdminUserFinance.call(
               member.id,
               tenant_context,
               Organizations.legacy_organization_slug()
             )

    assert id == member.id

    assert {:ok, %{user_id: ^id, executions: [], scores: []}} =
             GetAdminUserTrainingHistory.call(tenant_context, id)

    assert {:ok, %{user_id: ^id, visibility: "coach_role_required", prs: []}} =
             GetAdminUserPRs.call(tenant_context, id)

    assert {:ok, %{user_id: ^id, incidents: []}} = GetAdminUserIncidents.call(tenant_context, id)
    assert {:ok, %{user_id: ^id, threads: []}} = GetAdminUserMessages.call(tenant_context, id)

    assert {:ok, %{user_id: ^id, available: false, drill_down: nil}} =
             GetAdminUserCoachingContext.call(tenant_context, id, %{})
  end

  test "finance dossier includes package, referral, and referred-member context" do
    member = user_fixture(%{role: :member})
    referred = user_fixture(%{role: :member})
    tenant_context = legacy_tenant_context(member)

    Finance.with_tenant_context(tenant_context, fn ->
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
    end)

    assert {:ok, %{details: details}} =
             GetAdminUserFinance.call(
               member.id,
               tenant_context,
               Organizations.legacy_organization_slug()
             )

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
    coach_context = legacy_tenant_context(user_fixture(), :coach)

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: coach_context.organization_id,
        user_id: member.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    assert {:ok, pr} =
             Pantheon.create_record(%{
               "user_id" => member.id,
               "organization_id" => coach_context.organization_id,
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

    assert {:ok, %{visibility: "coach", prs: [%{history: [history]}]}} =
             GetAdminUserPRs.call(coach_context, member.id)

    assert history.beaten_on == "2026-07-01"
    assert Decimal.equal?(Decimal.new(to_string(history.score)), 100)
  end

  test "all focused reads return the same not-found boundary" do
    missing_id = Ecto.UUID.generate()
    tenant_context = legacy_tenant_context(admin_fixture())

    assert {:error, :not_found} = GetAdminUserPRs.call(tenant_context, missing_id)

    for service <- [
          GetAdminUserTrainingHistory,
          GetAdminUserIncidents,
          GetAdminUserMessages
        ] do
      assert {:error, :not_found} = service.call(tenant_context, missing_id)
    end

    assert {:error, :not_found} =
             GetAdminUserFinance.call(
               missing_id,
               tenant_context,
               Organizations.legacy_organization_slug()
             )

    assert {:error, :not_found} =
             GetAdminUserCoachingContext.call(tenant_context, missing_id, %{})
  end

  defp legacy_tenant_context(user, role \\ :owner) do
    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Dossier Test Gym #{System.unique_integer([:positive])}"
      })

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end
end
