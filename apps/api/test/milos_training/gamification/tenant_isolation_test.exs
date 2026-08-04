defmodule MilosTraining.Gamification.TenantIsolationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Gamification.GamificationStore
  alias MilosTraining.{Organizations, TestFixtures}

  test "seasonal challenges and opt-ins are isolated by organization context" do
    admin = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})
    context_a = tenant_context_fixture(admin, "First Gamification Gym")
    context_b = tenant_context_fixture(admin, "Second Gamification Gym")

    assert {:ok, challenge_a} =
             GamificationStore.with_tenant_context(context_a, fn ->
               GamificationStore.create_challenge(
                 challenge_params(context_a, admin, "January Push")
               )
             end)

    assert {:ok, challenge_b} =
             GamificationStore.with_tenant_context(context_b, fn ->
               GamificationStore.create_challenge(
                 challenge_params(context_b, admin, "January Push")
               )
             end)

    assert challenge_a.id != challenge_b.id

    assert [listed_a] =
             GamificationStore.with_tenant_context(context_a, fn ->
               GamificationStore.list_challenges()
             end)

    assert listed_a.id == challenge_a.id

    assert [listed_b] =
             GamificationStore.with_tenant_context(context_b, fn ->
               GamificationStore.list_challenges()
             end)

    assert listed_b.id == challenge_b.id

    assert {:ok, true} =
             GamificationStore.with_tenant_context(context_a, fn ->
               GamificationStore.set_leaderboard_opt_in(member.id, true)
             end)

    refute GamificationStore.with_tenant_context(context_b, fn ->
             GamificationStore.leaderboard_opted_in?(member.id)
           end)
  end

  defp challenge_params(context, admin, title) do
    %{
      organization_id: context.organization_id,
      title: title,
      description: "Tenant-scoped challenge",
      criteria_type: :workout_count,
      criteria_value: %{count: 3},
      badge_key: "tenant-january-push",
      badge_label: "January Push",
      starts_at: ~D[2026-01-01],
      ends_at: ~D[2026-01-31],
      created_by_id: admin.id
    }
  end

  defp tenant_context_fixture(owner, name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    context
  end
end
