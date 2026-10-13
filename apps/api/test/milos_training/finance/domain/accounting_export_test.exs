defmodule MilosTraining.Finance.Domain.AccountingExportTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.AccountingExport

  @today ~D[2026-10-12]

  describe "column schemas" do
    test "datasets and their column order are stable (schema version 1)" do
      assert AccountingExport.schema_version() == 1

      assert AccountingExport.dataset_names() ==
               ["payments", "allocations", "reversals", "credits", "refund_receipts"]

      assert AccountingExport.csv("payments", []) ==
               "payment_id,paid_on,recorded_at,member_user_id,member_name,membership_id," <>
                 "invoice_id,invoice_number,package_subscription_id,payment_method," <>
                 "payment_status,currency,amount_cents,reversed_cents,net_amount_cents\r\n"

      assert AccountingExport.csv("refund_receipts", []) ==
               "receipt_id,receipt_number,sequence,issued_at,reversal_id,payment_id,invoice_id," <>
                 "invoice_number,member_user_id,member_name,reversal_type,currency,amount_cents," <>
                 "reason,snapshot_sha256\r\n"
    end

    test "every column has a supported type" do
      for {_dataset, columns} <- AccountingExport.datasets(), {_name, type} <- columns do
        assert type in [:string, :integer, :date, :datetime]
      end
    end
  end

  describe "csv/2" do
    test "encodes typed cells, quotes delimiters and neutralizes formulas" do
      row = %{
        "reversal_id" => "rev-1",
        "occurred_on" => ~D[2026-10-02],
        "occurred_at" => ~U[2026-10-02 10:00:00Z],
        "reversal_type" => "refund",
        "amount_cents" => 1_250,
        "currency" => "EUR",
        "reason" => "=HYPERLINK(\"x\"), \"quoted\"\nnext",
        "member_name" => "-Dash",
        "refund_receipt_number" => "RFD-000001"
      }

      [_header, line, ""] = String.split(AccountingExport.csv("reversals", [row]), "\r\n")

      assert line ==
               "rev-1,2026-10-02,2026-10-02T10:00:00Z,refund,,,,,'-Dash,EUR,1250," <>
                 "\"'=HYPERLINK(\"\"x\"\"), \"\"quoted\"\"\nnext\",,RFD-000001"
    end

    test "negative integer amounts are not mistaken for formulas" do
      row = %{"entry_id" => "c-1", "amount_cents" => -500}
      [_header, line, ""] = String.split(AccountingExport.csv("credits", [row]), "\r\n")
      assert line == "c-1,,,,,,,,,,,-500,"
    end
  end

  test "json/2 keeps column order, types and raw integer amounts" do
    document =
      AccountingExport.json("credits", [%{"entry_id" => "c-1", "amount_cents" => -500}])
      |> Jason.decode!(objects: :ordered_objects)

    assert document["dataset"] == "credits"
    assert document["schema_version"] == 1
    [row] = document["rows"]

    assert Enum.map(row.values, &elem(&1, 0)) ==
             Enum.map(AccountingExport.columns("credits"), &elem(&1, 0))

    assert row["amount_cents"] == -500
    assert row["occurred_on"] == nil
  end

  describe "validate_range/3" do
    test "accepts an inclusive range and counts days" do
      assert {:ok, %{range_start: ~D[2026-10-01], range_end: ~D[2026-10-31], days: 31}} =
               AccountingExport.validate_range("2026-10-01", "2026-10-31", @today)
    end

    test "rejects reversed, malformed, future and overlong ranges" do
      assert {:error, :invalid_export_range} =
               AccountingExport.validate_range("2026-10-05", "2026-10-01", @today)

      assert {:error, :invalid_export_range} =
               AccountingExport.validate_range("oct", "2026-10-01", @today)

      assert {:error, :invalid_export_range} =
               AccountingExport.validate_range("2026-10-13", "2026-10-20", @today)

      assert {:error, :export_range_too_long} =
               AccountingExport.validate_range("2015-01-01", "2026-10-01", @today)
    end
  end

  test "ranges beyond the inline limit run in the background" do
    assert AccountingExport.execution_mode(31) == "inline"
    assert AccountingExport.execution_mode(32) == "background"
  end

  test "bundle/2 zips every dataset as CSV and JSON with a checksummed manifest" do
    meta = %{
      export_id: "exp-1",
      organization_id: "org-1",
      range_start: ~D[2026-10-01],
      range_end: ~D[2026-10-31],
      generated_at: ~U[2026-10-12 08:00:00Z]
    }

    rows = %{"payments" => [%{"payment_id" => "p-1", "amount_cents" => 100}]}

    assert {:ok, %{zip: zip, files: files, row_counts: row_counts}} =
             AccountingExport.bundle(meta, rows)

    assert row_counts["payments"] == 1
    assert row_counts["credits"] == 0

    {:ok, entries} = :zip.unzip(zip, [:memory])
    entries = Map.new(entries, fn {name, body} -> {List.to_string(name), body} end)

    assert Map.keys(entries) |> Enum.sort() ==
             Enum.sort(
               ["manifest.json"] ++
                 Enum.flat_map(AccountingExport.dataset_names(), &["#{&1}.csv", "#{&1}.json"])
             )

    for %{"name" => name, "sha256" => sha256, "byte_size" => size} <- files do
      assert AccountingExport.sha256(entries[name]) == sha256
      assert byte_size(entries[name]) == size
    end

    manifest = Jason.decode!(entries["manifest.json"])
    assert manifest["range_start"] == "2026-10-01"
    assert manifest["schema_version"] == 1
    assert length(manifest["files"]) == 10
  end

  test "artifacts live under the tenant finance export prefix" do
    assert AccountingExport.relative_object_key("exp-1") ==
             "finance/accounting-exports/exp-1/accounting-export.zip"
  end
end
