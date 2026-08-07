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

  test "record_event/1 derives organization_id from the session when the caller omits it" do
    # Every real call site (RecordAnalyticsEvent.call/2 and its ~20 callers)
    # omits organization_id - it relies on already running inside a
    # with_tenant_context/2 session. The test above always passed it
    # explicitly, which is why this gap went unnoticed: without it, every
    # analytics event and communication thread was persisted with
    # organization_id = NULL, invisible to any org's summary.
    admin = TestFixtures.admin_fixture()
    context = tenant_context_fixture(admin, "Implicit Org Analytics Gym")

    assert {:ok, event} =
             AnalyticsStore.with_tenant_context(context, fn ->
               AnalyticsStore.record_event(%{event_name: "implicit_org_event", user_id: admin.id})
             end)

    refute is_nil(event.organization_id)
    assert event.organization_id == context.organization_id

    summary =
      AnalyticsStore.with_tenant_context(context, fn ->
        AnalyticsStore.analytics_summary(%{"days" => 1})
      end)

    assert summary.events.by_name == %{"implicit_org_event" => 1}
  end

  test "get_or_create_communication_thread deduplicates within an organization when the caller omits organization_id" do
    admin = TestFixtures.admin_fixture()
    context = tenant_context_fixture(admin, "Implicit Org Thread Gym")
    context_id = Ecto.UUID.generate()

    thread_params = %{
      "context_type" => "direct",
      "context_id" => context_id,
      "sender_id" => admin.id,
      "sender_role_snapshot" => "admin",
      "direction" => "admin_to_user",
      "sent_at" => DateTime.utc_now()
    }

    {:ok, first} =
      AnalyticsStore.with_tenant_context(context, fn ->
        AnalyticsStore.record_communication_message(
          Map.merge(thread_params, %{"body" => "first"})
        )
      end)

    {:ok, second} =
      AnalyticsStore.with_tenant_context(context, fn ->
        AnalyticsStore.record_communication_message(
          Map.merge(thread_params, %{"body" => "second"})
        )
      end)

    # Without the fix, organization_id = NULL on every thread meant the
    # (organization_id, context_type, context_id) uniqueness never matched -
    # NULL is distinct from NULL in Postgres - so the second call would
    # silently create a duplicate thread instead of reusing the first.
    assert first.thread_id == second.thread_id
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
