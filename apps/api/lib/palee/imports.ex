defmodule Palee.Imports do
  @moduledoc """
  The Imports bounded context (ADR-254): moving a box's people and their
  history in from a CSV file.

    * upload: the file is decoded (`Encoding`), parsed (`CsvParser`) and its
      rows stored with a proposed mapping (`HeaderMatcher`, `Presets`);
    * dry run: every row is read (`RowPlan.read/3`), fingerprinted and
      planned against what the business has now, without writing anything
      outside this context;
    * apply, report, invitations and undo are run by
      `Palee.Application.Imports.*`, which writes through the services of
      Identity, Organizations, Finance and Facility and records here what
      each row did.

  Imports never reads other contexts' tables: callers hand it what it needs
  to know about the business (`index` in `RowPlan.match/2`).
  """

  alias Palee.Imports.Domain.{
    CsvParser,
    DateParser,
    Encoding,
    Fields,
    HeaderMatcher,
    ImportPolicy,
    Presets,
    RowPlan,
    TenantDataPolicy,
    Values
  }

  alias Palee.Imports.ImportStore

  @guess_sample 500

  # ── Ports ───────────────────────────────────────────────────────────────

  @doc "The configured clock (`Imports.Ports.Clock`)."
  def clock, do: Application.fetch_env!(:palee, :import_clock)
  def now, do: clock().now()

  def transaction(context, fun), do: ImportStore.transaction(context, fun)

  # ── Catalog ─────────────────────────────────────────────────────────────

  @doc "What the import screens offer: fields, presets, orders, limits and codes."
  def catalog do
    %{
      fields: Fields.all(),
      presets: Enum.map(Presets.all(), &Presets.public/1),
      date_orders: DateParser.orders(),
      roles: ImportPolicy.roles(),
      limits: ImportPolicy.limits(),
      statuses: ImportPolicy.statuses(),
      row_statuses: ImportPolicy.row_statuses(),
      outcomes: ImportPolicy.outcomes(),
      warnings: ImportPolicy.warnings(),
      errors: ImportPolicy.errors(),
      encodings: Encoding.encodings()
    }
  end

  # ── Upload ──────────────────────────────────────────────────────────────

  @doc """
  Stores an uploaded file as a draft import with a proposed mapping.
  `upload`: `%{filename, content, source}` (`source` a preset key or nil to
  detect). `{:ok, import}` or `{:error, code}`.
  """
  def upload(context, %{filename: filename, content: content} = upload, actor_id)
      when is_binary(content) do
    source = Map.get(upload, :source)

    with :ok <- ImportPolicy.check_size(byte_size(content)),
         :ok <- check_source(source),
         {:ok, text, encoding, file_warnings} <- Encoding.to_utf8(content),
         {:ok, parsed} <- CsvParser.parse(text),
         :ok <- ImportPolicy.check_rows(length(parsed.rows)) do
      suggestion = HeaderMatcher.suggest(parsed.header, source)

      attrs = %{
        created_by_id: actor_id,
        status: "draft",
        source: suggestion.source,
        filename: filename |> to_string() |> Path.basename() |> String.slice(0, 255),
        byte_size: byte_size(content),
        sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
        encoding: encoding,
        delimiter: parsed.delimiter,
        header: parsed.header,
        row_count: length(parsed.rows),
        mapping: Enum.map(suggestion.mapping, &Map.take(&1, [:column, :field])),
        date_order: guess_date_order(parsed.rows, suggestion),
        default_role: "member",
        file_warnings: Enum.map(file_warnings, &Atom.to_string/1)
      }

      rows =
        parsed.rows
        |> Enum.with_index(1)
        |> Enum.map(fn {cells, number} -> %{row_number: number, cells: cells} end)

      ImportStore.insert_import(context, attrs, rows)
    end
  end

  defp check_source(nil), do: :ok

  defp check_source(source),
    do: if(source in Presets.keys(), do: :ok, else: {:error, :invalid_source})

  defp guess_date_order(rows, %{mapping: mapping, date_order: default}) do
    date_columns =
      for %{column: column, field: field} <- mapping,
          field && Fields.type(field) == "date",
          do: column

    values =
      rows
      |> Enum.take(@guess_sample)
      |> Enum.flat_map(fn cells -> Enum.map(date_columns, &Enum.at(cells, &1)) end)

    DateParser.guess_order(values, default) || default
  end

  # ── Reading ─────────────────────────────────────────────────────────────

  def get(context, id), do: ImportStore.get_import(context, id, [])
  def get_for_update(context, id), do: ImportStore.get_import(context, id, lock: true)
  def list(context, filters \\ %{}), do: ImportStore.list_imports(context, filters)
  def rows(context, import_id, filters), do: ImportStore.list_rows(context, import_id, filters)
  def row_counts(context, import_id), do: ImportStore.row_counts(context, import_id)
  def update(context, id, changes), do: ImportStore.update_import(context, id, changes)
  def delete(context, id), do: ImportStore.delete_import(context, id)

  @doc """
  Changes the mapping and options of a draft. `params`: `mapping`
  (`[%{column, field}]`), `date_order`, `default_role`, each optional.
  """
  def configure(context, import, params) do
    mapping = Map.get(params, :mapping) || import.mapping

    options = %{
      date_order: Map.get(params, :date_order) || import.date_order,
      default_role: Map.get(params, :default_role) || import.default_role
    }

    with true <- ImportPolicy.editable?(import) || {:error, :import_not_editable},
         {:ok, mapped} <- ImportPolicy.validate_mapping(mapping, length(import.header)),
         {:ok, options} <- ImportPolicy.validate_options(options) do
      full =
        import.header
        |> Enum.with_index()
        |> Enum.map(fn {_header, column} ->
          %{column: column, field: Enum.find_value(mapped, &(&1.column == column && &1.field))}
        end)

      ImportStore.update_import(context, import.id, Map.put(options, :mapping, full))
    end
  end

  @doc "The mapping of an import as `RowPlan.read/3` takes it (mapped columns only)."
  def mapped_columns(import) do
    case ImportPolicy.validate_mapping(import.mapping, length(import.header)) do
      {:ok, mapped} -> {:ok, mapped}
      error -> error
    end
  end

  def options(import), do: %{date_order: import.date_order, default_role: import.default_role}

  @doc "Reads one row's cells: `%{values, warnings, fingerprint}`."
  def read_row(import, mapped, row) do
    %{values: values, warnings: warnings} = RowPlan.read(row.cells, mapped, options(import))
    %{values: values, warnings: warnings, fingerprint: RowPlan.fingerprint(values)}
  end

  # ── Dry run ─────────────────────────────────────────────────────────────

  @doc """
  Plans every pending row and saves the outcomes and the counts.
  `business_index` gets the emails of the file and answers what the caller
  knows of the business (see `RowPlan.match/2`, plus `package_names`: the
  folded names of its packages). `{:ok, import}`.
  """
  def dry_run(context, import, business_index, %DateTime{} = now)
      when is_function(business_index, 1) do
    with {:ok, mapped} <- mapped_columns(import) do
      rows = ImportStore.list_rows(context, import.id, %{limit: :all})
      read = Enum.map(rows, &Map.merge(&1, read_row(import, mapped, &1)))
      applied = ImportStore.applied_fingerprints(context, Enum.map(read, & &1.fingerprint))
      emails = read |> Enum.map(& &1.values["email"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      index = Map.merge(people_index(context), business_index.(emails))

      {plans, _state} =
        Enum.map_reduce(read, %{index: index, seen: %{}}, fn row, state ->
          plan_row(row, state, applied)
        end)

      :ok = ImportStore.save_plans(context, import.id, plans)

      preview = %{
        rows: length(plans),
        outcomes: Enum.frequencies_by(plans, & &1.outcome),
        actions: plans |> Enum.flat_map(& &1.actions) |> Enum.frequencies(),
        warnings: plans |> Enum.flat_map(& &1.warnings) |> Enum.frequencies_by(& &1.code)
      }

      ImportStore.update_import(context, import.id, %{preview: preview, previewed_at: now})
    end
  end

  defp plan_row(row, %{index: index, seen: seen} = state, applied) do
    values = row.values
    match = RowPlan.match(values, index)
    names = index[:package_names] || MapSet.new()

    facts = %{
      person: match,
      already_imported?: MapSet.member?(applied, row.fingerprint),
      duplicate_of: Map.get(seen, row.fingerprint),
      package_exists?:
        is_binary(values["package_name"]) and
          MapSet.member?(names, Values.fold(values["package_name"]))
    }

    plan = RowPlan.plan(values, facts, row.warnings)

    index =
      if plan.outcome == "create_person" do
        index
        |> put_planned(:planned_by_email, values["email"], row.row_number)
        |> put_planned(:planned_by_phone, Values.phone_key(values["phone"]), row.row_number)
      else
        index
      end

    names =
      if :create_package in plan.actions,
        do: MapSet.put(names, Values.fold(values["package_name"])),
        else: names

    saved = %{
      row_number: row.row_number,
      outcome: plan.outcome,
      fingerprint: row.fingerprint,
      warnings: plan.warnings,
      errors: plan.errors,
      actions: plan.actions
    }

    {saved,
     %{
       state
       | index: Map.put(index, :package_names, names),
         seen: Map.put_new(seen, row.fingerprint, row.row_number)
     }}
  end

  defp put_planned(index, _key, nil, _row), do: index

  defp put_planned(index, key, value, row),
    do: Map.update(index, key, %{value => row}, &Map.put_new(&1, value, row))

  @doc "What imports know of people they brought in, as `RowPlan.match/2` reads it."
  def people_index(context) do
    people = context |> ImportStore.list_people() |> Enum.sort_by(& &1.inserted_at, DateTime)

    %{
      people_by_email: index_people(people, :email),
      people_by_phone: index_people(people, :phone_key)
    }
  end

  defp index_people(people, key) do
    Enum.reduce(people, %{}, fn person, acc ->
      case Map.get(person, key) do
        nil -> acc
        value -> Map.put_new(acc, value, person.user_id)
      end
    end)
  end

  # ── Applying rows (called by the application layer) ─────────────────────

  def lock_row(context, row_id), do: ImportStore.lock_row(context, row_id)
  def update_row(context, row_id, changes), do: ImportStore.update_row(context, row_id, changes)

  def applied?(context, fingerprint),
    do: context |> ImportStore.applied_fingerprints([fingerprint]) |> MapSet.member?(fingerprint)

  def find_person(context, key, value), do: ImportStore.find_person(context, key, value)
  def save_person(context, attrs), do: ImportStore.upsert_person(context, attrs)
  def update_person(context, id, changes), do: ImportStore.update_person(context, id, changes)
  def people_of_import(context, import_id), do: ImportStore.people_of_import(context, import_id)

  # ── Tenant data (ADR-117) ───────────────────────────────────────────────

  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
