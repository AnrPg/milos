defmodule Palee.Finance.ReconciliationAndExportsTest do
  @moduledoc """
  ADR-126 payment-provider reconciliation (idempotent recording, matching
  rules, one fact per line, two-tenant isolation) and accounting exports
  (contents, checksums, tenant object prefix, ADR-117 inventory/purge,
  background mode) under the RLS-enforcing runtime role.
  """

  use Palee.DataCase, async: false
  use Oban.Testing, repo: Palee.Repo

  @moduletag :rls_enforced

  alias Palee.Application.{
    BuildFinanceAccountingExport,
    GetFinanceAccountingExportDownload,
    GetFinanceReconciliationCandidates,
    ListFinanceAccountingExports,
    ListFinanceReconciliationRecords,
    MatchFinanceReconciliationRecord,
    RecordFinanceReconciliationLine,
    RequestFinanceAccountingExport,
    ReverseFinancePayment,
    TenantObjectStorage,
    UnmatchFinanceReconciliationRecord
  }

  alias Palee.Finance
  alias Palee.Finance.Domain.AccountingExport
  alias Palee.Organizations
  alias Palee.TestFixtures
  alias Palee.TestSupport.MemoryObjectStore
  alias Palee.Workers.BuildFinanceAccountingExportJob

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    :ok
  end

  defp tenant(name) do
    bypass_rls(fn ->
      owner = TestFixtures.admin_fixture()
      member = TestFixtures.user_fixture(%{role: :member})

      {:ok, organization} =
        Organizations.create_organization(%{
          name: "#{name} #{System.unique_integer([:positive])}"
        })

      for {user, role} <- [{owner, :owner}, {member, :member}] do
        {:ok, _} =
          Organizations.add_membership(%{
            organization_id: organization.id,
            user_id: user.id,
            role: role,
            status: :active,
            joined_at: DateTime.utc_now()
          })
      end

      {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
      %{organization: organization, owner: owner, member: member, context: context}
    end)
  end

  defp payment(%{context: context, member: member}, amount_cents, paid_on \\ Date.utc_today()) do
    {:ok, membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, payment} =
      Finance.record_payment(context, membership.id, %{
        amount_cents: amount_cents,
        payment_method: "card_manual",
        payment_status: "paid",
        paid_on: paid_on
      })

    payment
  end

  defp refund(tenant, payment, amount_cents) do
    {:ok, reversal} =
      Finance.with_tenant_context(tenant.context, fn ->
        ReverseFinancePayment.call(
          tenant.context,
          tenant.member.id,
          payment.id,
          tenant.owner.id,
          %{
            "amount_cents" => amount_cents,
            "reason" => "Refund, \"partial\"",
            "request_id" => Ecto.UUID.generate()
          }
        )
      end)

    reversal
  end

  defp line(overrides \\ %{}) do
    Map.merge(
      %{
        "provider" => "stripe",
        "external_reference" => "ch_#{System.unique_integer([:positive])}",
        "external_type" => "payment",
        "statement_amount_cents" => 5_000,
        "statement_currency" => "EUR",
        "statement_occurred_on" => Date.to_iso8601(Date.utc_today())
      },
      overrides
    )
  end

  describe "reconciliation" do
    test "recording is idempotent on provider and external reference" do
      tenant = tenant("Recon Gym")
      params = line(%{"external_reference" => "ch_same"})

      assert {:ok, record, :created} =
               RecordFinanceReconciliationLine.call(tenant.context, tenant.owner.id, params)

      assert record.status == "unmatched"
      assert record.recorded_by_id == tenant.owner.id

      assert {:ok, replay, :replayed} =
               RecordFinanceReconciliationLine.call(tenant.context, tenant.owner.id, params)

      assert replay.id == record.id

      assert {:error, :reconciliation_reference_conflict} =
               RecordFinanceReconciliationLine.call(
                 tenant.context,
                 tenant.owner.id,
                 Map.put(params, "statement_amount_cents", 4_999)
               )

      assert {:error, [statement_currency: _]} =
               RecordFinanceReconciliationLine.call(
                 tenant.context,
                 tenant.owner.id,
                 line(%{"statement_currency" => "euro"})
               )

      assert {:ok, %{reconciliation_records: [_]}} =
               ListFinanceReconciliationRecords.call(tenant.context, %{})
    end

    test "matching flags discrepancies and a fact links to one statement line only" do
      tenant = tenant("Match Gym")
      exact = payment(tenant, 5_000)

      {:ok, record, :created} =
        RecordFinanceReconciliationLine.call(tenant.context, tenant.owner.id, line())

      assert {:ok, %{candidates: [candidate | _]}} =
               GetFinanceReconciliationCandidates.call(tenant.context, record.id)

      assert candidate.target_id == exact.id
      assert candidate.member_name == tenant.member.nickname
      assert candidate.evaluation == %{status: "matched", discrepancies: []}

      assert {:ok, matched} =
               MatchFinanceReconciliationRecord.call(
                 tenant.context,
                 record.id,
                 tenant.owner.id,
                 %{
                   "target_type" => "payment",
                   "target_id" => exact.id
                 }
               )

      assert matched.status == "matched"
      assert matched.target_type == "payment"
      assert matched.membership_payment_id == exact.id
      assert matched.matched_by_id == tenant.owner.id

      {:ok, short, :created} =
        RecordFinanceReconciliationLine.call(
          tenant.context,
          tenant.owner.id,
          line(%{"statement_amount_cents" => 4_000, "external_status" => "pending"})
        )

      assert {:error, :reconciliation_target_already_matched} =
               MatchFinanceReconciliationRecord.call(tenant.context, short.id, tenant.owner.id, %{
                 "target_type" => "payment",
                 "target_id" => exact.id
               })

      other = payment(tenant, 4_500)

      assert {:ok, mismatched} =
               MatchFinanceReconciliationRecord.call(tenant.context, short.id, tenant.owner.id, %{
                 "target_type" => "payment",
                 "target_id" => other.id,
                 "notes" => "Provider fee withheld"
               })

      assert mismatched.status == "mismatched"
      assert mismatched.discrepancies == ["amount_mismatch", "provider_not_settled"]
      assert mismatched.discrepancy_notes == "Provider fee withheld"

      assert {:ok, cleared} =
               UnmatchFinanceReconciliationRecord.call(
                 tenant.context,
                 short.id,
                 tenant.owner.id,
                 %{}
               )

      assert cleared.status == "unmatched"
      assert cleared.membership_payment_id == nil

      assert {:error, :invalid_reconciliation_target} =
               MatchFinanceReconciliationRecord.call(tenant.context, short.id, tenant.owner.id, %{
                 "target_type" => "invoice",
                 "target_id" => other.id
               })
    end

    test "a refund line reconciles against a reversal fact" do
      tenant = tenant("Refund Recon Gym")
      reversal = refund(tenant, payment(tenant, 5_000), 2_000)

      {:ok, record, :created} =
        RecordFinanceReconciliationLine.call(
          tenant.context,
          tenant.owner.id,
          line(%{"external_type" => "refund", "statement_amount_cents" => 2_000})
        )

      assert {:ok, %{candidates: [%{target_type: "reversal", target_id: target_id}]}} =
               GetFinanceReconciliationCandidates.call(tenant.context, record.id)

      assert target_id == reversal.id

      assert {:ok, %{status: "matched", target_type: "reversal"}} =
               MatchFinanceReconciliationRecord.call(
                 tenant.context,
                 record.id,
                 tenant.owner.id,
                 %{
                   "target_type" => "reversal",
                   "target_id" => reversal.id
                 }
               )
    end

    test "tenants cannot see or match each other's records and facts" do
      first = tenant("Recon Tenant A")
      second = tenant("Recon Tenant B")
      first_payment = payment(first, 5_000)
      params = line(%{"external_reference" => "ch_shared"})

      {:ok, first_record, :created} =
        RecordFinanceReconciliationLine.call(first.context, first.owner.id, params)

      # The same provider reference is independent per organization.
      assert {:ok, second_record, :created} =
               RecordFinanceReconciliationLine.call(second.context, second.owner.id, params)

      refute second_record.id == first_record.id

      assert {:ok, %{reconciliation_records: [%{id: id}]}} =
               ListFinanceReconciliationRecords.call(second.context, %{})

      assert id == second_record.id

      assert {:error, :not_found} =
               MatchFinanceReconciliationRecord.call(
                 second.context,
                 second_record.id,
                 second.owner.id,
                 %{"target_type" => "payment", "target_id" => first_payment.id}
               )

      assert {:error, :not_found} =
               GetFinanceReconciliationCandidates.call(second.context, first_record.id)

      assert {:ok, %{candidates: []}} =
               GetFinanceReconciliationCandidates.call(second.context, second_record.id)
    end
  end

  describe "accounting exports" do
    test "an inline export stores a checksummed ZIP of every dataset under the tenant prefix" do
      tenant = tenant("Export Gym")
      other = tenant("Export Gym Other")
      paid = payment(tenant, 5_000)
      reversal = refund(tenant, paid, 1_250)
      _outside = payment(tenant, 9_999, Date.add(Date.utc_today(), -90))
      today = Date.to_iso8601(Date.utc_today())

      assert {:ok, export} =
               RequestFinanceAccountingExport.call(tenant.context, tenant.owner.id, %{
                 "range_start" => Date.to_iso8601(Date.add(Date.utc_today(), -6)),
                 "range_end" => today
               })

      assert export.status == "completed"
      assert export.execution_mode == "inline"
      assert export.requested_by_id == tenant.owner.id
      assert export.row_counts["payments"] == 1
      assert export.row_counts["reversals"] == 1
      assert export.row_counts["refund_receipts"] == 1

      prefix = "organizations/#{tenant.organization.id}/finance/accounting-exports/#{export.id}/"
      assert export.object_key == prefix <> "accounting-export.zip"

      {:ok, zip} = MemoryObjectStore.get(:documents, export.object_key)
      assert AccountingExport.sha256(zip) == export.sha256
      assert byte_size(zip) == export.byte_size

      {:ok, entries} = :zip.unzip(zip, [:memory])
      files = Map.new(entries, fn {name, body} -> {List.to_string(name), body} end)

      for %{"name" => name, "sha256" => sha256} <- export.files do
        assert AccountingExport.sha256(files[name]) == sha256
      end

      [header, payment_row, ""] = String.split(files["payments.csv"], "\r\n")
      assert header =~ "payment_id,paid_on"
      assert payment_row =~ paid.id
      assert payment_row =~ tenant.member.nickname
      assert payment_row =~ ",5000,1250,3750"

      assert files["reversals.csv"] =~ reversal.id
      assert files["reversals.csv"] =~ "\"Refund, \"\"partial\"\"\""
      assert files["reversals.csv"] =~ reversal.refund_receipt.receipt_number
      assert files["refund_receipts.csv"] =~ reversal.refund_receipt.snapshot_sha256

      # ADR-117: the artifact is part of the tenant inventory and purge.
      {:ok, %{documents: documents}} = TenantObjectStorage.inventory(tenant.organization.id, [])
      assert Enum.any?(documents, &(&1.key == export.object_key))

      assert {:ok, %{download_url: url, expires_in_seconds: 900, sha256: sha256}} =
               GetFinanceAccountingExportDownload.call(tenant.context, export.id)

      assert url =~ export.object_key
      assert sha256 == export.sha256

      assert {:error, :not_found} =
               GetFinanceAccountingExportDownload.call(other.context, export.id)

      assert {:ok, %{accounting_exports: []}} =
               ListFinanceAccountingExports.call(other.context, %{})

      assert {:ok, %{accounting_exports: [%{id: listed_id}]}} =
               ListFinanceAccountingExports.call(tenant.context, %{})

      assert listed_id == export.id

      assert {:ok, %{deleted_objects: deleted}} =
               TenantObjectStorage.purge_tenant_objects(
                 tenant.organization.id,
                 Finance.tenant_data_policy().retained_object_prefixes
               )

      assert deleted >= 1
      assert MemoryObjectStore.get(:documents, export.object_key) == :error
    end

    test "large ranges are queued and built by the background job" do
      tenant = tenant("Background Export Gym")
      _paid = payment(tenant, 7_000, Date.add(Date.utc_today(), -40))

      assert {:ok, export} =
               RequestFinanceAccountingExport.call(tenant.context, tenant.owner.id, %{
                 "range_start" => Date.to_iso8601(Date.add(Date.utc_today(), -60)),
                 "range_end" => Date.to_iso8601(Date.utc_today())
               })

      assert export.status == "queued"
      assert export.execution_mode == "background"

      args = %{"organization_id" => tenant.organization.id, "export_id" => export.id}
      assert_enqueued(worker: BuildFinanceAccountingExportJob, args: args)
      assert :ok = perform_job(BuildFinanceAccountingExportJob, args)

      assert {:ok, %{download_url: _}} =
               GetFinanceAccountingExportDownload.call(tenant.context, export.id)

      assert %{status: "completed", row_counts: %{"payments" => 1}} =
               Finance.get_accounting_export(tenant.context, export.id)

      # Re-running a completed export is a no-op.
      assert {:ok, %{sha256: sha256}} =
               BuildFinanceAccountingExport.call(tenant.context, export.id)

      assert sha256 == Finance.get_accounting_export(tenant.context, export.id).sha256
    end

    test "invalid ranges are rejected before a run is recorded" do
      tenant = tenant("Range Gym")

      assert {:error, :invalid_export_range} =
               RequestFinanceAccountingExport.call(tenant.context, tenant.owner.id, %{
                 "range_start" => "2026-10-10",
                 "range_end" => "2026-10-01"
               })

      assert {:error, :export_range_too_long} =
               RequestFinanceAccountingExport.call(tenant.context, tenant.owner.id, %{
                 "range_start" => "2015-01-01",
                 "range_end" => "2021-01-01"
               })

      assert {:ok, %{accounting_exports: []}} =
               ListFinanceAccountingExports.call(tenant.context, %{})

      assert {:error, :accounting_export_not_ready} =
               (fn ->
                  {:ok, queued} =
                    Finance.create_accounting_export(tenant.context, %{
                      range_start: ~D[2026-01-01],
                      range_end: ~D[2026-01-02],
                      execution_mode: "inline",
                      schema_version: 1
                    })

                  GetFinanceAccountingExportDownload.call(tenant.context, queued.id)
                end).()
    end
  end
end
