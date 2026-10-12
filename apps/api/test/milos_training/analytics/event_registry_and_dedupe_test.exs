defmodule MilosTraining.Analytics.EventRegistryAndDedupeTest do
  @moduledoc "ADR-113: registry enforcement and per-tenant dedupe in the Analytics context."
  use MilosTraining.DataCase, async: false

  import MilosTraining.AnalyticsHelpers

  alias MilosTraining.Analytics

  test "record_event/1 refuses names missing from the registry" do
    {organization, owner, context} = organization_fixture()

    assert {:error, :unknown_analytics_event} =
             Analytics.with_tenant_context(context, fn ->
               Analytics.record_event(%{event_name: "not_registered", user_id: owner.id})
             end)

    assert analytics_events(organization.id, "not_registered") == []
  end

  test "a repeated dedupe key is a no-op within a tenant but not across tenants" do
    {org_a, owner, context_a} = organization_fixture()
    {org_b, _owner_b, context_b} = organization_fixture(owner)

    params = %{
      event_name: "workout_execution_abandoned",
      user_id: owner.id,
      dedupe_key: "execution-1"
    }

    assert {:ok, %{id: _}} =
             Analytics.with_tenant_context(context_a, fn -> Analytics.record_event(params) end)

    assert {:ok, :duplicate} =
             Analytics.with_tenant_context(context_a, fn -> Analytics.record_event(params) end)

    assert {:ok, %{id: _}} =
             Analytics.with_tenant_context(context_b, fn -> Analytics.record_event(params) end)

    assert [_] = analytics_events(org_a.id, "workout_execution_abandoned")
    assert [_] = analytics_events(org_b.id, "workout_execution_abandoned")

    assert ["execution-1"] =
             Analytics.with_tenant_context(context_a, fn ->
               Analytics.list_recorded_dedupe_keys("workout_execution_abandoned", [
                 "execution-1",
                 "execution-2"
               ])
             end)
  end

  test "events without a dedupe key are always recorded" do
    {organization, owner, context} = organization_fixture()

    for _ <- 1..2 do
      Analytics.with_tenant_context(context, fn ->
        Analytics.record_event(%{event_name: "class_slot_cancelled", user_id: owner.id})
      end)
    end

    assert length(analytics_events(organization.id, "class_slot_cancelled")) == 2
  end

  test "record_events/1 reports inserted and duplicate counts" do
    {_organization, owner, context} = organization_fixture()

    batch =
      for key <- ["a", "b"],
          do: %{event_name: "execution_interaction", user_id: owner.id, dedupe_key: key}

    assert {:ok, %{inserted: 2, duplicates: 0}} =
             Analytics.with_tenant_context(context, fn -> Analytics.record_events(batch) end)

    assert {:ok, %{inserted: 1, duplicates: 2}} =
             Analytics.with_tenant_context(context, fn ->
               Analytics.record_events(
                 batch ++
                   [%{event_name: "execution_interaction", user_id: owner.id, dedupe_key: "c"}]
               )
             end)
  end
end
