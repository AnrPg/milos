defmodule MilosTraining.AnalyticsHelpers do
  @moduledoc """
  Test helpers for ADR-113 instrumentation tests: tenant fixtures and direct
  reads of persisted `analytics_events` rows (the test DB role bypasses RLS,
  so rows are filtered by organization explicitly).
  """

  import Ecto.Query

  alias MilosTraining.Analytics.AnalyticsEvent
  alias MilosTraining.{Organizations, Repo, TestFixtures}

  def organization_fixture(owner \\ nil) do
    owner = owner || TestFixtures.admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Analytics Gym #{System.unique_integer([:positive])}"
      })

    add_membership(organization, owner, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    {organization, owner, context}
  end

  def member_context(organization, role \\ :member) do
    account_role = if role == :athlete, do: :athlete, else: :member
    user = TestFixtures.user_fixture(%{role: account_role})
    add_membership(organization, user, role)
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    {user, context}
  end

  def add_membership(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    user
  end

  def analytics_events(organization_id, event_name) do
    AnalyticsEvent
    |> where([e], e.organization_id == ^organization_id and e.event_name == ^event_name)
    |> order_by([e], asc: e.occurred_at)
    |> Repo.all()
  end

  def analytics_event!(organization_id, event_name) do
    case analytics_events(organization_id, event_name) do
      [event] -> event
      events -> raise "expected one #{event_name} event, got #{length(events)}"
    end
  end
end
