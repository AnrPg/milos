defmodule MilosTraining.Coaching.TenantIsolationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Coaching.CoachingStore
  alias MilosTraining.{Organizations, TestFixtures}

  test "aggregates fail closed when no organization context is open" do
    # get_aggregates/0 reads app.organization_id directly. With no tenant open
    # it must decline rather than fall through to an unscoped read of every
    # organization's coaching_aggregates rows.
    aggregates = CoachingStore.get_aggregates()

    assert aggregates.aggregate_status == "unavailable"
    assert aggregates.aggregate_error == "missing_organization_scope"
    assert aggregates.active_athlete_count == 0
    assert aggregates.completed_workouts_this_week == 0
  end

  test "each organization context resolves aggregates under its own scope" do
    admin = TestFixtures.admin_fixture()
    context_a = tenant_context_fixture(admin, "First Coaching Gym")
    context_b = tenant_context_fixture(admin, "Second Coaching Gym")

    assert :ok = CoachingStore.refresh_aggregates()

    aggregates_a =
      CoachingStore.with_tenant_context(context_a, fn -> CoachingStore.get_aggregates() end)

    aggregates_b =
      CoachingStore.with_tenant_context(context_b, fn -> CoachingStore.get_aggregates() end)

    # Neither context may report the "no scope" sentinel: opening a tenant must
    # actually reach the organization-filtered query.
    for aggregates <- [aggregates_a, aggregates_b] do
      refute aggregates[:aggregate_error] == "missing_organization_scope"
    end

    # Both organizations are empty, so neither may pick up the other's athletes.
    assert aggregates_a.active_athlete_count == 0
    assert aggregates_b.active_athlete_count == 0
    assert aggregates_a.completed_workouts_this_week == 0
    assert aggregates_b.completed_workouts_this_week == 0
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
