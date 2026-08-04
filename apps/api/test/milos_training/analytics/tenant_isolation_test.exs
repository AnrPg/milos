defmodule MilosTraining.Analytics.TenantIsolationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Analytics.AnalyticsStore
  alias MilosTraining.{Organizations, TestFixtures}

  test "events and summaries are isolated by organization context" do
    admin = TestFixtures.admin_fixture()
    context_a = tenant_context_fixture(admin, "First Analytics Gym")
    context_b = tenant_context_fixture(admin, "Second Analytics Gym")

    assert {:ok, _event_a} =
             AnalyticsStore.with_tenant_context(context_a, fn ->
               AnalyticsStore.record_event(%{
                 organization_id: context_a.organization_id,
                 event_name: "tenant_a_event",
                 user_id: admin.id
               })
             end)

    assert {:ok, _event_b} =
             AnalyticsStore.with_tenant_context(context_b, fn ->
               AnalyticsStore.record_event(%{
                 organization_id: context_b.organization_id,
                 event_name: "tenant_b_event",
                 user_id: admin.id
               })
             end)

    summary_a =
      AnalyticsStore.with_tenant_context(context_a, fn ->
        AnalyticsStore.analytics_summary(%{"days" => 1})
      end)

    summary_b =
      AnalyticsStore.with_tenant_context(context_b, fn ->
        AnalyticsStore.analytics_summary(%{"days" => 1})
      end)

    assert summary_a.events.by_name == %{"tenant_a_event" => 1}
    assert summary_b.events.by_name == %{"tenant_b_event" => 1}
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
