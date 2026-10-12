defmodule MilosTraining.Application.OrganizationPurgeRLSTest do
  @moduledoc """
  ADR-099 under real Row Level Security.

  The suite normally runs as a superuser, which bypasses RLS, so a root-tenant
  table query that is not wrapped in `RepoContext.run/2` passes every ordinary
  test and only fails in production. This test seeds two tenants as the
  superuser, then switches the sandbox transaction to the non-superuser runtime
  role (`SET LOCAL ROLE`) and drives the whole request -> export -> approve ->
  purge workflow through the real application services.
  """

  use MilosTraining.DataCase, async: false

  import MilosTraining.TenantPurgeFixtures
  import MilosTraining.TestFixtures

  alias MilosTraining.{Identity, Organizations, RLSCase}

  alias MilosTraining.Application.{
    ApproveOrganizationPurge,
    ExecuteOrganizationPurge,
    ExportOrganizationTenantData,
    RequestOrganizationPurge
  }

  setup do
    RLSCase.ensure_runtime_role!()

    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:milos_training, Oban), :testing, :manual)}
    )

    vendor = user_fixture()
    {:ok, _} = Organizations.grant_vendor(vendor.id)
    doomed = seed_tenant("RLS Doomed Gym")
    survivor = seed_tenant("RLS Survivor Gym")

    %{vendor: vendor, doomed: doomed, survivor: survivor}
  end

  test "the full workflow succeeds as the non-superuser runtime role", ctx do
    org_id = ctx.doomed.organization.id
    survivor_counts = tenant_row_counts(ctx.survivor.organization.id)
    doomed_counts = tenant_row_counts(org_id)

    Repo.query!("SET LOCAL ROLE #{RLSCase.runtime_role()}")

    assert %{rows: [[false]]} =
             Repo.query!("SELECT rolbypassrls FROM pg_roles WHERE rolname = current_user")

    # RLS really is enforced here: without session GUCs nothing is visible,
    # including the root organizations table an unwrapped query would read.
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM notifications")
    assert is_nil(Organizations.get_by_id(org_id))

    {:ok, platform} = Organizations.resolve_platform_context(ctx.vendor)

    assert {:ok, purge} = RequestOrganizationPurge.call(platform, org_id)
    assert {:ok, exported} = ExportOrganizationTenantData.call(platform, purge.id)
    assert exported.status == :exported

    # Personal tables (owner-only RLS) were read through per-user sessions.
    review = Map.new(exported.retention_review, &{&1["context"], &1})

    assert resource_count(review, "notifications", "notifications") ==
             doomed_counts["notifications"]

    assert resource_count(review, "pantheon", "user_pr_records") ==
             doomed_counts["user_pr_records"]

    assert resource_count(review, "finance", "finance_invoices") == 1

    assert {:ok, _approved} =
             ApproveOrganizationPurge.call(platform, org_id, %{
               "confirmation" => ctx.doomed.organization.slug
             })

    assert {:ok, completed} = ExecuteOrganizationPurge.call(platform, purge.id)
    assert completed.status == :completed
    assert completed.steps["notifications"]["deleted"]["notifications"] == 1
    assert completed.steps["gamification"]["deleted"]["user_achievements"] == 1

    refute Identity.find_by_id(ctx.doomed.member.id)

    Repo.query!("RESET ROLE")
    assert tenant_row_counts(org_id) |> Map.values() |> Enum.all?(&(&1 == 0))
    assert tenant_row_counts(ctx.survivor.organization.id) == survivor_counts
  end

  defp resource_count(review, context, resource) do
    review[context]["resources"]
    |> Enum.find(&(&1["resource"] == resource))
    |> Map.fetch!("count")
  end
end
