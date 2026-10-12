defmodule MilosTraining.Finance.Domain.AccountingExport do
  @moduledoc """
  Stable accounting-export schemas and artifact building (ADR-116).

  An export covers an inclusive date range and produces, per dataset, one
  CSV (RFC 4180, UTF-8, CRLF, header row) and one JSON document with the
  same columns, bundled with a `manifest.json` (per-file SHA-256, byte size
  and row count) into a single ZIP. Column names, order and types are
  versioned by `schema_version/0`; a breaking change must bump it.

  Amounts are integer minor units (cents) - never floats. Dates are ISO 8601
  (`YYYY-MM-DD`), timestamps ISO 8601 UTC. Text cells that a spreadsheet
  would evaluate as a formula (`= + - @`, tab, CR) are prefixed with `'`.

  Range semantics (business date): payments by `paid_on`, allocations by
  the payment `paid_on` or credit `occurred_on`, reversals and credits by
  `occurred_on`, refund receipts by the UTC date of `issued_at`.
  Soft-deleted facts (ADR-084) are excluded.
  """

  @schema_version 1
  @inline_max_days 31
  @max_range_days 1830

  @datasets [
    {"payments",
     [
       {"payment_id", :string},
       {"paid_on", :date},
       {"recorded_at", :datetime},
       {"member_user_id", :string},
       {"member_name", :string},
       {"membership_id", :string},
       {"invoice_id", :string},
       {"invoice_number", :string},
       {"package_subscription_id", :string},
       {"payment_method", :string},
       {"payment_status", :string},
       {"currency", :string},
       {"amount_cents", :integer},
       {"reversed_cents", :integer},
       {"net_amount_cents", :integer}
     ]},
    {"allocations",
     [
       {"allocation_id", :string},
       {"allocation_type", :string},
       {"occurred_on", :date},
       {"invoice_id", :string},
       {"invoice_number", :string},
       {"source_payment_id", :string},
       {"source_credit_entry_id", :string},
       {"member_user_id", :string},
       {"member_name", :string},
       {"currency", :string},
       {"amount_cents", :integer},
       {"reversed_cents", :integer},
       {"net_amount_cents", :integer}
     ]},
    {"reversals",
     [
       {"reversal_id", :string},
       {"occurred_on", :date},
       {"occurred_at", :datetime},
       {"reversal_type", :string},
       {"payment_id", :string},
       {"invoice_id", :string},
       {"invoice_number", :string},
       {"member_user_id", :string},
       {"member_name", :string},
       {"currency", :string},
       {"amount_cents", :integer},
       {"reason", :string},
       {"recorded_by_id", :string},
       {"refund_receipt_number", :string}
     ]},
    {"credits",
     [
       {"entry_id", :string},
       {"occurred_on", :date},
       {"occurred_at", :datetime},
       {"entry_type", :string},
       {"source_type", :string},
       {"member_user_id", :string},
       {"member_name", :string},
       {"payment_id", :string},
       {"invoice_id", :string},
       {"reversed_entry_id", :string},
       {"currency", :string},
       {"amount_cents", :integer},
       {"description", :string}
     ]},
    {"refund_receipts",
     [
       {"receipt_id", :string},
       {"receipt_number", :string},
       {"sequence", :integer},
       {"issued_at", :datetime},
       {"reversal_id", :string},
       {"payment_id", :string},
       {"invoice_id", :string},
       {"invoice_number", :string},
       {"member_user_id", :string},
       {"member_name", :string},
       {"reversal_type", :string},
       {"currency", :string},
       {"amount_cents", :integer},
       {"reason", :string},
       {"snapshot_sha256", :string}
     ]}
  ]

  def schema_version, do: @schema_version
  def inline_max_days, do: @inline_max_days
  def max_range_days, do: @max_range_days

  @doc "Ordered `{dataset, [{column, type}]}` schema list."
  def datasets, do: @datasets

  def dataset_names, do: Enum.map(@datasets, &elem(&1, 0))

  def columns(dataset) do
    case List.keyfind(@datasets, dataset, 0) do
      {^dataset, columns} -> columns
      nil -> raise ArgumentError, "unknown accounting export dataset #{inspect(dataset)}"
    end
  end

  @doc """
  Validates an inclusive range. `today` bounds the start date (an export
  cannot start in the future).
  """
  def validate_range(range_start, range_end, %Date{} = today) do
    with {:ok, start_date} <- parse_date(range_start),
         {:ok, end_date} <- parse_date(range_end),
         :ok <- ordered(start_date, end_date),
         :ok <- not_future(start_date, today),
         days = Date.diff(end_date, start_date) + 1,
         :ok <- within_limit(days) do
      {:ok, %{range_start: start_date, range_end: end_date, days: days}}
    end
  end

  @doc "Ranges longer than #{@inline_max_days} days are built by a background job."
  def execution_mode(days) when is_integer(days) and days > @inline_max_days, do: "background"
  def execution_mode(days) when is_integer(days), do: "inline"

  @doc "Object key relative to the tenant prefix."
  def relative_object_key(export_id) when is_binary(export_id),
    do: "finance/accounting-exports/#{export_id}/accounting-export.zip"

  @doc "Renders one dataset as CSV."
  def csv(dataset, rows) when is_list(rows) do
    columns = columns(dataset)
    header = Enum.map_join(columns, ",", fn {name, _type} -> name end)

    body =
      Enum.map(rows, fn row ->
        Enum.map_join(columns, ",", fn {name, type} -> csv_cell(cell(row, name), type) end)
      end)

    Enum.map_join([header | body], "", &(&1 <> "\r\n"))
  end

  @doc "Renders one dataset as a canonical JSON document."
  def json(dataset, rows) when is_list(rows) do
    columns = columns(dataset)

    Jason.OrderedObject.new([
      {"dataset", dataset},
      {"schema_version", @schema_version},
      {"columns",
       Enum.map(columns, fn {name, type} ->
         Jason.OrderedObject.new([{"name", name}, {"type", Atom.to_string(type)}])
       end)},
      {"rows",
       Enum.map(rows, fn row ->
         columns
         |> Enum.map(fn {name, type} -> {name, json_value(cell(row, name), type)} end)
         |> Jason.OrderedObject.new()
       end)}
    ])
    |> Jason.encode!(pretty: true)
  end

  @doc """
  Builds the ZIP bundle. `meta` carries `:export_id`, `:organization_id`,
  `:range_start`, `:range_end` and `:generated_at`; `rows` maps each dataset
  name to its rows. Returns the ZIP binary plus the file manifest and row
  counts recorded on the export run.
  """
  def bundle(meta, rows) when is_map(rows) do
    files =
      Enum.flat_map(dataset_names(), fn dataset ->
        dataset_rows = Map.get(rows, dataset, [])

        [
          {"#{dataset}.csv", csv(dataset, dataset_rows), length(dataset_rows)},
          {"#{dataset}.json", json(dataset, dataset_rows), length(dataset_rows)}
        ]
      end)

    file_manifest =
      Enum.map(files, fn {name, body, row_count} ->
        %{
          "name" => name,
          "sha256" => sha256(body),
          "byte_size" => byte_size(body),
          "rows" => row_count
        }
      end)

    row_counts = Map.new(dataset_names(), &{&1, length(Map.get(rows, &1, []))})
    manifest = manifest_json(meta, file_manifest, row_counts)

    entries =
      [{"manifest.json", manifest} | Enum.map(files, fn {name, body, _rows} -> {name, body} end)]
      |> Enum.map(fn {name, body} -> {String.to_charlist(name), body} end)

    case :zip.create(~c"accounting-export.zip", entries, [:memory]) do
      {:ok, {_name, zip}} ->
        {:ok, %{zip: zip, files: file_manifest, row_counts: row_counts, manifest: manifest}}

      {:error, reason} ->
        {:error, {:accounting_export_bundle_failed, reason}}
    end
  end

  @doc "Lower-case hex SHA-256."
  def sha256(binary) when is_binary(binary),
    do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  defp manifest_json(meta, files, row_counts) do
    Jason.OrderedObject.new([
      {"export_id", meta.export_id},
      {"organization_id", meta.organization_id},
      {"schema_version", @schema_version},
      {"range_start", Date.to_iso8601(meta.range_start)},
      {"range_end", Date.to_iso8601(meta.range_end)},
      {"generated_at", DateTime.to_iso8601(meta.generated_at)},
      {"row_counts", row_counts |> Enum.sort() |> Jason.OrderedObject.new()},
      {"files",
       Enum.map(files, fn file ->
         Jason.OrderedObject.new(
           Enum.map(["name", "sha256", "byte_size", "rows"], &{&1, file[&1]})
         )
       end)},
      {"datasets",
       Enum.map(@datasets, fn {dataset, columns} ->
         Jason.OrderedObject.new([
           {"name", dataset},
           {"columns", Enum.map(columns, fn {name, type} -> "#{name}:#{type}" end)}
         ])
       end)}
    ])
    |> Jason.encode!(pretty: true)
  end

  # Rows are string-keyed maps whose keys are the column names.
  defp cell(row, name), do: Map.get(row, name)

  defp csv_cell(nil, _type), do: ""
  defp csv_cell(value, :integer) when is_integer(value), do: Integer.to_string(value)
  defp csv_cell(%Date{} = value, :date), do: Date.to_iso8601(value)
  defp csv_cell(%DateTime{} = value, :datetime), do: DateTime.to_iso8601(value)
  defp csv_cell(%NaiveDateTime{} = value, :datetime), do: NaiveDateTime.to_iso8601(value) <> "Z"
  defp csv_cell(value, _type), do: value |> to_string() |> guard_formula() |> quote_csv()

  defp json_value(nil, _type), do: nil
  defp json_value(value, :integer) when is_integer(value), do: value
  defp json_value(%Date{} = value, :date), do: Date.to_iso8601(value)
  defp json_value(%DateTime{} = value, :datetime), do: DateTime.to_iso8601(value)
  defp json_value(%NaiveDateTime{} = value, :datetime), do: NaiveDateTime.to_iso8601(value) <> "Z"
  defp json_value(value, _type), do: to_string(value)

  defp guard_formula(<<first, _rest::binary>> = value) when first in [?=, ?+, ?-, ?@, ?\t, ?\r],
    do: "'" <> value

  defp guard_formula(value), do: value

  defp quote_csv(value) do
    if String.contains?(value, [",", "\"", "\r", "\n"]),
      do: "\"" <> String.replace(value, "\"", "\"\"") <> "\"",
      else: value
  end

  defp parse_date(%Date{} = date), do: {:ok, date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_export_range}
    end
  end

  defp parse_date(_value), do: {:error, :invalid_export_range}

  defp ordered(start_date, end_date) do
    if Date.compare(end_date, start_date) == :lt, do: {:error, :invalid_export_range}, else: :ok
  end

  defp not_future(start_date, today) do
    if Date.compare(start_date, today) == :gt, do: {:error, :invalid_export_range}, else: :ok
  end

  defp within_limit(days) when days > @max_range_days, do: {:error, :export_range_too_long}
  defp within_limit(_days), do: :ok
end
