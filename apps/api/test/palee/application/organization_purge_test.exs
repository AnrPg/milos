defmodule Palee.Application.OrganizationPurgeTest do
  @moduledoc """
  ADR-117 reviewed tenant export/purge: staged workflow, context-by-context
  purge in dependency order, two-tenant isolation, idempotent re-runs, and an
  audit record that survives the purge.
  """

  use Palee.DataCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Palee.TenantPurgeFixtures
  import Palee.TestFixtures

  alias Palee.{Identity, Organizations}

  alias Palee.Application.{
    ApproveOrganizationPurge,
    CancelOrganizationPurge,
    ChangeOrganizationLifecycle,
    ExecuteOrganizationPurge,
    ExportOrganizationTenantData,
    GetOrganizationPurgeStatus,
    RequestOrganizationPurge,
    ResumeOrganizationPurge
  }

  alias Palee.Organizations.Organization
  alias Palee.TestSupport.MemoryObjectStore
  alias Palee.Workers.{ExecuteOrganizationPurgeJob, ExportOrganizationTenantDataJob}

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    vendor = user_fixture()
    second_vendor = user_fixture()
    {:ok, _} = Organizations.grant_vendor(vendor.id)
    {:ok, _} = Organizations.grant_vendor(second_vendor.id)
    {:ok, platform} = Organizations.resolve_platform_context(vendor)
    {:ok, second_platform} = Organizations.resolve_platform_context(second_vendor)

    shared = user_fixture()
    doomed = seed_tenant("Doomed Purge Gym", shared_user: shared)
    survivor = seed_tenant("Survivor Purge Gym", shared_user: shared)

    %{
      platform: platform,
      second_platform: second_platform,
      shared: shared,
      doomed: doomed,
      survivor: survivor
    }
  end

  test "request suspends the tenant, records the purge and enqueues the export", ctx do
    org_id = ctx.doomed.organization.id

    assert {:ok, purge} = RequestOrganizationPurge.call(ctx.platform, org_id)
    assert purge.status == :requested
    assert purge.organization_slug == ctx.doomed.organization.slug
    assert Repo.get!(Organization, org_id).status == :suspended

    assert_enqueued(
      worker: ExportOrganizationTenantDataJob,
      args: %{"purge_id" => purge.id, "actor_user_id" => ctx.platform.user_id}
    )

    assert {:error, :organization_purge_exists} =
             RequestOrganizationPurge.call(ctx.platform, org_id)
  end

  test "export writes per-context JSON, objects manifest and a retention review", ctx do
    org_id = ctx.doomed.organization.id
    {:ok, purge} = RequestOrganizationPurge.call(ctx.platform, org_id)

    assert :ok =
             perform_job(ExportOrganizationTenantDataJob, %{
               "purge_id" => purge.id,
               "actor_user_id" => ctx.platform.user_id
             })

    {:ok, %{purge: purge, export_download_url: url}} =
      GetOrganizationPurgeStatus.call(ctx.platform, org_id)

    assert purge.status == :exported
    assert url =~ purge.export_key
    assert String.starts_with?(purge.export_key, "organizations/#{org_id}/purge/#{purge.id}/")
    assert purge.export_byte_size > 0
    assert String.length(purge.export_sha256) == 64

    files = unzip(:documents, purge.export_key)

    for context <-
          ~w(analytics notifications execution pantheon feedback wellbeing messaging gamification finance scheduling workouts organizations) do
      assert Map.has_key?(files, "contexts/#{context}.json"), "missing #{context} export"
    end

    finance = files["contexts/finance.json"]
    assert finance["disposition"] == "retain"
    assert [%{"organization_id" => ^org_id}] = finance["tables"]["finance_invoices"]

    assert [_member_notification] =
             files["contexts/notifications.json"]["tables"]["notifications"]

    assert [_pr] = files["contexts/pantheon.json"]["tables"]["user_pr_records"]

    invitations = files["contexts/organizations.json"]["tables"]["registration_invitations"]
    refute Enum.any?(invitations, &Map.has_key?(&1, "token_digest"))

    accounts = files["identity/accounts.json"]["accounts"]
    assert Enum.any?(accounts, &(&1["id"] == ctx.doomed.member.id))
    refute Enum.any?(accounts, &Map.has_key?(&1, "password_hash"))

    manifest = files["storage/objects-manifest.json"]
    document_keys = Enum.map(manifest["documents"], & &1["key"])
    assert ctx.doomed.invoice_key in document_keys
    refute ctx.survivor.invoice_key in document_keys
    assert ctx.doomed.avatar_key in Enum.map(manifest["avatars"], & &1["key"])

    assert files["manifest.json"]["format"] == "palee-tenant-export/v1"

    review = Map.new(purge.retention_review, &{&1["context"], &1})
    assert review["finance"]["disposition"] == "retain"
    assert review["finance"]["retain_years"] == 10

    assert review["finance"]["retained_until"] ==
             Date.to_iso8601(Date.shift(Date.utc_today(), year: 10))

    assert review["finance"]["record_count"] > 0
    assert review["analytics"]["disposition"] == "retain_anonymized"
    assert review["workouts"]["disposition"] == "purge"
    # owner + member are tenant-only; the shared account also belongs to the survivor.
    assert review["identity"]["record_count"] == 2

    assert %{"resource" => "shared_accounts_kept", "count" => 1} in review["identity"][
             "resources"
           ]

    assert %{"resource" => "retained_documents", "count" => 1} in review["storage"]["resources"]

    retained = unzip(:documents, purge.retained_archive_key)

    assert Map.keys(retained) |> Enum.sort() ==
             ~w(contexts/analytics.json contexts/documents.json contexts/finance.json contexts/fiscal.json contexts/shop.json retention-manifest.json)

    assert [_invoice] = retained["contexts/finance.json"]["tables"]["finance_invoices"]
  end

  test "approval requires a completed export and the typed organization slug", ctx do
    org_id = ctx.doomed.organization.id
    {:ok, _purge} = RequestOrganizationPurge.call(ctx.platform, org_id)

    assert {:error, :invalid_purge_transition} =
             ApproveOrganizationPurge.call(ctx.platform, org_id, %{
               "confirmation" => ctx.doomed.organization.slug
             })

    export!(ctx.platform, org_id)

    assert {:error, :purge_confirmation_mismatch} =
             ApproveOrganizationPurge.call(ctx.platform, org_id, %{"confirmation" => "nope"})

    assert {:ok, purge} =
             ApproveOrganizationPurge.call(ctx.second_platform, org_id, %{
               "confirmation" => " #{ctx.doomed.organization.slug} "
             })

    assert purge.status == :approved
    assert purge.approval_mode == "second_vendor"
    assert purge.approved_by_user_id == ctx.second_platform.user_id

    assert_enqueued(worker: ExecuteOrganizationPurgeJob, args: %{"purge_id" => purge.id})
  end

  test "purging tenant A removes only A's data, objects and tenant-only accounts", ctx do
    org_id = ctx.doomed.organization.id
    survivor_id = ctx.survivor.organization.id
    survivor_counts = tenant_row_counts(survivor_id)

    assert Enum.all?(
             ~w(finance_invoices master_workouts scheduled_classes notifications user_pr_records user_achievements gamification_settings),
             &(survivor_counts[&1] > 0)
           )

    purge = approve!(ctx, org_id)

    assert :ok =
             perform_job(ExecuteOrganizationPurgeJob, %{
               "purge_id" => purge.id,
               "actor_user_id" => ctx.platform.user_id
             })

    assert {:ok, purge} = Organizations.get_organization_purge_by_id(ctx.platform, purge.id)
    assert purge.status == :completed

    # Tenant A is gone across every context; tenant B is untouched.
    refute Repo.get(Organization, org_id)
    assert tenant_row_counts(org_id) |> Map.values() |> Enum.all?(&(&1 == 0))
    assert tenant_row_counts(survivor_id) == survivor_counts

    # Tenant-only accounts and their avatars go; shared accounts stay.
    refute Identity.find_by_id(ctx.doomed.member.id)
    refute Identity.find_by_id(ctx.doomed.owner.id)
    assert Identity.find_by_id(ctx.shared.id)
    assert Identity.find_by_id(ctx.survivor.member.id)
    assert :error = MemoryObjectStore.get(:avatars, ctx.doomed.avatar_key)
    assert {:ok, _} = MemoryObjectStore.get(:avatars, ctx.survivor.avatar_key)

    # Objects: retained archive and finance documents survive; the rest of A goes.
    assert {:ok, _} = MemoryObjectStore.get(:documents, purge.retained_archive_key)
    assert {:ok, _} = MemoryObjectStore.get(:documents, ctx.doomed.invoice_key)
    assert :error = MemoryObjectStore.get(:documents, ctx.doomed.logo_key)
    assert :error = MemoryObjectStore.get(:documents, purge.export_key)
    assert {:ok, _} = MemoryObjectStore.get(:documents, ctx.survivor.logo_key)

    # The audit trail survives without PII: identifiers, counts and policies.
    assert purge.steps["finance"]["deleted"]["finance_invoices"] == 1
    assert purge.steps["workouts"]["deleted"]["master_workouts"] == 1
    assert purge.steps["identity"]["deleted_accounts"] == 2
    assert purge.steps["storage"]["deleted_objects"] >= 2
    assert purge.steps["organizations"]["status"] == "completed"
    refute inspect(purge) =~ ctx.doomed.member.email

    assert {:ok, %{purge: %{status: :completed}, export_download_url: nil}} =
             GetOrganizationPurgeStatus.call(ctx.platform, org_id)
  end

  test "an owner whose own logo change is in the audit log is purged with the tenant", ctx do
    org_id = ctx.doomed.organization.id

    # A tenant logo change records the owner as the event's actor.
    Repo.insert!(%Palee.Organizations.OrganizationProvisioningEvent{
      organization_id: org_id,
      vendor_user_id: ctx.doomed.owner.id,
      event: "organization_logo_uploaded",
      metadata: %{"actor_scope" => "tenant"}
    })

    purge = approve!(ctx, org_id)
    assert {:ok, %{status: :completed}} = ExecuteOrganizationPurge.call(ctx.platform, purge.id)
    refute Identity.find_by_id(ctx.doomed.owner.id)
  end

  test "re-running the purge is idempotent and resumes after a partial run", ctx do
    org_id = ctx.doomed.organization.id
    survivor_counts = tenant_row_counts(ctx.survivor.organization.id)
    purge = approve!(ctx, org_id)

    # Simulate a crash after the first steps: run them, leave the rest.
    {:ok, purging} =
      Organizations.advance_organization_purge(ctx.platform, purge.id, :start_purge)

    {:ok, scope} = Organizations.tenant_purge_context(ctx.platform, purging)
    {:ok, deleted} = Palee.Analytics.purge_tenant_data(scope)

    {:ok, _} =
      Organizations.record_organization_purge_step(ctx.platform, purge.id, "analytics", %{
        deleted: deleted
      })

    {:ok, _} =
      Organizations.advance_organization_purge(ctx.platform, purge.id, :fail, %{
        stage: "purge",
        reason: :simulated_crash
      })

    assert {:ok, failed} = Organizations.get_organization_purge(ctx.platform, org_id)
    assert failed.status == :failed
    assert failed.failure_reason == "simulated_crash"

    assert {:ok, _} = ResumeOrganizationPurge.call(ctx.platform, org_id)
    assert_enqueued(worker: ExecuteOrganizationPurgeJob, args: %{"purge_id" => purge.id})

    assert {:ok, completed} = ExecuteOrganizationPurge.call(ctx.platform, purge.id)
    assert completed.status == :completed

    assert completed.steps["analytics"]["completed_at"] ==
             failed.steps["analytics"]["completed_at"]

    # A second full run is a no-op.
    assert {:ok, again} = ExecuteOrganizationPurge.call(ctx.platform, purge.id)
    assert again.status == :completed
    assert again.updated_at == completed.updated_at
    assert tenant_row_counts(ctx.survivor.organization.id) == survivor_counts
  end

  test "an open purge pins the lifecycle until it is cancelled", ctx do
    org_id = ctx.doomed.organization.id
    {:ok, purge} = RequestOrganizationPurge.call(ctx.platform, org_id)
    purge = export!(ctx.platform, org_id) || purge

    assert {:error, :organization_purge_in_progress} =
             ChangeOrganizationLifecycle.call(ctx.platform, org_id, "active")

    assert {:ok, %{status: :archived}} =
             ChangeOrganizationLifecycle.call(ctx.platform, org_id, "archived")

    assert {:ok, cancelled} = CancelOrganizationPurge.call(ctx.platform, org_id)
    assert cancelled.status == :cancelled
    assert cancelled.cancelled_by_user_id == ctx.platform.user_id
    assert :error = MemoryObjectStore.get(:documents, purge.export_key)
    assert :error = MemoryObjectStore.get(:documents, purge.retained_archive_key)
    assert {:ok, _} = MemoryObjectStore.get(:documents, ctx.doomed.logo_key)

    assert {:ok, %{status: :active}} =
             ChangeOrganizationLifecycle.call(ctx.platform, org_id, "active")

    # A cancelled purge is closed: there is nothing left to approve.
    assert {:error, :not_found} =
             ApproveOrganizationPurge.call(ctx.platform, org_id, %{
               "confirmation" => ctx.doomed.organization.slug
             })
  end

  test "an approved purge cannot be cancelled or have its lifecycle changed", ctx do
    org_id = ctx.doomed.organization.id
    _purge = approve!(ctx, org_id)

    assert {:error, :invalid_purge_transition} =
             CancelOrganizationPurge.call(ctx.platform, org_id)

    assert {:error, :organization_purge_in_progress} =
             ChangeOrganizationLifecycle.call(ctx.platform, org_id, "archived")
  end

  test "context purge functions fail closed without a purge context", ctx do
    assert {:error, :organization_context_required} =
             Palee.Finance.purge_tenant_data(ctx.doomed.context)

    assert {:error, :organization_context_required} =
             Palee.Workouts.export_tenant_data(nil)

    {:ok, purge} =
      Organizations.request_organization_purge(ctx.platform, ctx.doomed.organization.id)

    assert {:error, :invalid_purge_transition} =
             Organizations.tenant_purge_context(ctx.platform, purge.purge)
  end

  test "export and purge jobs discard work for a vendor that lost authority", ctx do
    org_id = ctx.doomed.organization.id
    {:ok, purge} = RequestOrganizationPurge.call(ctx.platform, org_id)
    {:ok, _} = Organizations.revoke_vendor(ctx.platform.user_id)

    assert {:cancel, :vendor_required} =
             perform_job(ExportOrganizationTenantDataJob, %{
               "purge_id" => purge.id,
               "actor_user_id" => ctx.platform.user_id
             })
  end

  defp export!(platform, organization_id) do
    {:ok, purge} = Organizations.get_organization_purge(platform, organization_id)
    {:ok, purge} = ExportOrganizationTenantData.call(platform, purge.id)
    purge
  end

  defp approve!(ctx, organization_id) do
    {:ok, _purge} = RequestOrganizationPurge.call(ctx.platform, organization_id)
    export!(ctx.platform, organization_id)

    {:ok, purge} =
      ApproveOrganizationPurge.call(ctx.platform, organization_id, %{
        "confirmation" => ctx.doomed.organization.slug
      })

    assert purge.approval_mode == "typed_confirmation"
    purge
  end

  defp unzip(bucket, key) do
    {:ok, body} = MemoryObjectStore.get(bucket, key)
    {:ok, files} = :zip.unzip(body, [:memory])
    Map.new(files, fn {name, json} -> {to_string(name), Jason.decode!(json)} end)
  end
end
