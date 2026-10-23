defmodule Palee.TenantData.Domain.RetentionReviewTest do
  use ExUnit.Case, async: true

  alias Palee.Application.TenantDataContexts
  alias Palee.TenantData.Domain.{ExportBundle, RetentionReview}

  @retained %{
    context: "ledger",
    purge_order: 5,
    disposition: :retain,
    retain_years: 10,
    tables: [%{table: "ledger_entries"}],
    retained_object_prefixes: ["invoices/"]
  }

  test "normalize! fills defaults and rejects unsafe or incomplete policies" do
    policy = RetentionReview.normalize!(@retained)
    assert policy.excluded_columns == []
    assert policy.anonymized_columns == []

    assert_raise ArgumentError, fn ->
      RetentionReview.normalize!(%{@retained | tables: [%{table: "x; DROP TABLE users"}]})
    end

    assert_raise ArgumentError, fn ->
      RetentionReview.normalize!(%{@retained | retain_years: nil})
    end
  end

  test "retention deadlines follow the policy" do
    policy = RetentionReview.normalize!(@retained)
    assert RetentionReview.retained_until(policy, ~D[2026-10-12]) == ~D[2036-10-12]
    assert RetentionReview.retained_until(%{disposition: :purge}, ~D[2026-10-12]) == nil
  end

  test "entry summarises counts per resource" do
    policy = RetentionReview.normalize!(@retained)

    entry =
      RetentionReview.entry(
        policy,
        [%{resource: "ledger_entries", count: 3}, %{resource: "other", count: 2}],
        ~D[2026-10-12]
      )

    assert entry["record_count"] == 5
    assert entry["disposition"] == "retain"
    assert entry["retained_until"] == "2036-10-12"
  end

  test "retained object prefixes include the archive prefix and retaining contexts only" do
    purge_policy = %{disposition: :purge, retained_object_prefixes: ["ignored/"]}

    assert RetentionReview.retained_object_prefixes([
             RetentionReview.normalize!(@retained),
             purge_policy
           ]) ==
             ["retained/", "invoices/"]
  end

  test "storage entry separates retained from purgeable documents" do
    documents = [
      %{key: "organizations/o/invoices/1/a.pdf", size: 1},
      %{key: "organizations/o/branding/logo.png", size: 1}
    ]

    entry =
      RetentionReview.storage_entry(documents, [%{key: "users/u/avatars/a.png", size: 1}], [
        "invoices/"
      ])

    assert %{"resource" => "retained_documents", "count" => 1} in entry["resources"]
    assert %{"resource" => "tenant_documents", "count" => 1} in entry["resources"]
    assert %{"resource" => "account_avatars", "count" => 1} in entry["resources"]
  end

  test "strip_columns removes secrets and identifiers" do
    assert RetentionReview.strip_columns([%{"id" => 1, "user_id" => 2}], ["user_id"]) == [
             %{"id" => 1}
           ]
  end

  test "context policies are ordered so dependents purge before what they reference" do
    order = TenantDataContexts.policies() |> Enum.map(& &1.context)

    assert Enum.find_index(order, &(&1 == "analytics")) <
             Enum.find_index(order, &(&1 == "scheduling"))

    assert Enum.find_index(order, &(&1 == "scheduling")) <
             Enum.find_index(order, &(&1 == "workouts"))

    assert Enum.find_index(order, &(&1 == "execution")) <
             Enum.find_index(order, &(&1 == "workouts"))

    assert Enum.find_index(order, &(&1 == "analytics")) <
             Enum.find_index(order, &(&1 == "notifications"))
  end

  test "only finance and its shop source documents retain records in full; analytics retains anonymized events" do
    by_context = Map.new(TenantDataContexts.policies(), &{&1.context, &1})

    assert by_context["finance"].disposition == :retain
    assert by_context["finance"].retain_years == 10
    assert "invoices/" in by_context["finance"].retained_object_prefixes
    assert by_context["analytics"].disposition == :retain_anonymized
    assert "user_id" in by_context["analytics"].anonymized_columns

    # ADR-190: shop orders are the source rows of Finance's shop revenue.
    assert by_context["shop"].disposition == :retain
    assert by_context["shop"].retain_years == by_context["finance"].retain_years

    assert by_context
           |> Map.drop(["finance", "shop", "analytics"])
           |> Map.values()
           |> Enum.all?(&(&1.disposition == :purge))
  end

  test "export bundles are zip files of JSON documents" do
    policy = RetentionReview.normalize!(@retained)

    {:ok, zip} =
      ExportBundle.full_export(%{
        purge_id: "p",
        organization: %{"id" => "o", "slug" => "gym"},
        generated_at: ~U[2026-10-12 10:00:00Z],
        sections: [%{policy: policy, tables: %{"ledger_entries" => [%{"id" => 1}]}}],
        accounts: [],
        objects: %{documents: [], avatars: []},
        retention_review: []
      })

    {:ok, files} = :zip.unzip(zip, [:memory])
    names = Enum.map(files, fn {name, _} -> to_string(name) end)

    assert "manifest.json" in names
    assert "contexts/ledger.json" in names
    assert "storage/objects-manifest.json" in names
    assert String.length(ExportBundle.sha256(zip)) == 64
  end
end
