defmodule Palee.Infrastructure.Imports.EctoImportStore do
  @moduledoc "Ecto adapter of the import store (ADR-254)."

  @behaviour Palee.Imports.Ports.ImportStore

  import Ecto.Query

  alias Palee.Imports.{Import, ImportedPerson, ImportRow}
  alias Palee.Repo

  @insert_chunk 1_000
  @plan_chunk 2_000
  @max_page 500

  @impl true
  def transaction(_context, fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Imports ─────────────────────────────────────────────────────────────

  @impl true
  def insert_import(%{organization_id: organization_id}, attrs, rows) do
    Repo.transaction(fn ->
      import =
        %Import{organization_id: organization_id}
        |> Import.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, import} -> import
          {:error, changeset} -> Repo.rollback(changeset)
        end

      now = DateTime.utc_now()

      rows
      |> Enum.chunk_every(@insert_chunk)
      |> Enum.each(fn chunk ->
        entries =
          Enum.map(chunk, fn row ->
            %{
              id: Ecto.UUID.generate(),
              organization_id: organization_id,
              import_id: import.id,
              row_number: row.row_number,
              cells: row.cells,
              status: "pending",
              warnings: [],
              errors: [],
              result: %{},
              inserted_at: now,
              updated_at: now
            }
          end)

        Repo.insert_all(ImportRow, entries)
      end)

      plain(import)
    end)
  end

  @impl true
  def get_import(%{organization_id: organization_id}, id, opts) do
    query = from i in Import, where: i.organization_id == ^organization_id and i.id == ^id
    query = if opts[:lock], do: lock(query, "FOR UPDATE"), else: query
    query |> Repo.one() |> plain()
  end

  @impl true
  def list_imports(%{organization_id: organization_id}, filters) do
    Import
    |> where([i], i.organization_id == ^organization_id)
    |> order_by([i], desc: i.inserted_at, desc: i.id)
    |> limit(^min(filters[:limit] || 50, 200))
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @impl true
  def update_import(%{organization_id: organization_id}, id, changes) do
    case Repo.one(from i in Import, where: i.organization_id == ^organization_id and i.id == ^id) do
      nil ->
        {:error, :not_found}

      import ->
        import
        |> Import.changeset(changes)
        |> Repo.update()
        |> case do
          {:ok, import} -> {:ok, plain(import)}
          error -> error
        end
    end
  end

  @impl true
  def delete_import(%{organization_id: organization_id}, id) do
    Repo.delete_all(from i in Import, where: i.organization_id == ^organization_id and i.id == ^id)
    :ok
  end

  # ── Rows ────────────────────────────────────────────────────────────────

  @impl true
  def list_rows(%{organization_id: organization_id}, import_id, filters) do
    ImportRow
    |> where([r], r.organization_id == ^organization_id and r.import_id == ^import_id)
    |> filter_row(:status, filters[:status])
    |> filter_row(:outcome, filters[:outcome])
    |> filter_after(filters[:after_row])
    |> order_by([r], asc: r.row_number)
    |> maybe_limit(filters[:limit])
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  defp filter_row(query, _field, nil), do: query

  defp filter_row(query, field, values) when is_list(values),
    do: where(query, [r], field(r, ^field) in ^values)

  defp filter_row(query, field, value), do: where(query, [r], field(r, ^field) == ^value)

  defp filter_after(query, nil), do: query
  defp filter_after(query, row), do: where(query, [r], r.row_number > ^row)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, :all), do: query
  defp maybe_limit(query, limit), do: limit(query, ^min(limit, @max_page))

  @impl true
  def save_plans(%{organization_id: organization_id}, import_id, plans) do
    plans
    |> Enum.chunk_every(@plan_chunk)
    |> Enum.each(fn chunk ->
      Repo.query!(
        """
        UPDATE import_rows AS r
           SET outcome = v.outcome,
               fingerprint = v.fingerprint,
               warnings = ARRAY(SELECT jsonb_array_elements(v.warnings)),
               errors = ARRAY(SELECT jsonb_array_elements(v.errors)),
               updated_at = now()
          FROM jsonb_to_recordset($3::jsonb)
               AS v(row_number int, outcome text, fingerprint text, warnings jsonb, errors jsonb)
         WHERE r.organization_id = $1 AND r.import_id = $2 AND r.row_number = v.row_number
           AND r.status = 'pending'
        """,
        [
          Ecto.UUID.dump!(organization_id),
          Ecto.UUID.dump!(import_id),
          Enum.map(chunk, &Map.take(&1, [:row_number, :outcome, :fingerprint, :warnings, :errors]))
        ]
      )
    end)

    :ok
  end

  @impl true
  def lock_row(%{organization_id: organization_id}, id) do
    ImportRow
    |> where([r], r.organization_id == ^organization_id and r.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> plain()
  end

  @impl true
  def update_row(%{organization_id: organization_id}, id, changes) do
    case Repo.one(
           from r in ImportRow, where: r.organization_id == ^organization_id and r.id == ^id
         ) do
      nil ->
        {:error, :not_found}

      row ->
        row
        |> ImportRow.changeset(changes)
        |> Repo.update()
        |> case do
          {:ok, row} ->
            {:ok, plain(row)}

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            if Keyword.has_key?(errors, :fingerprint),
              do: {:error, :already_imported},
              else: {:error, changeset}
        end
    end
  end

  @impl true
  def applied_fingerprints(_context, []), do: MapSet.new()

  def applied_fingerprints(%{organization_id: organization_id}, fingerprints) do
    fingerprints
    |> Enum.uniq()
    |> Enum.chunk_every(5_000)
    |> Enum.flat_map(fn chunk ->
      ImportRow
      |> where(
        [r],
        r.organization_id == ^organization_id and r.fingerprint in ^chunk and
          r.status == "applied"
      )
      |> select([r], r.fingerprint)
      |> Repo.all()
    end)
    |> MapSet.new()
  end

  @impl true
  def row_counts(%{organization_id: organization_id}, import_id) do
    base =
      from r in ImportRow,
        where: r.organization_id == ^organization_id and r.import_id == ^import_id

    statuses =
      base
      |> group_by([r], r.status)
      |> select([r], {r.status, count(r.id)})
      |> Repo.all()
      |> Map.new()

    outcomes =
      base
      |> where([r], not is_nil(r.outcome))
      |> group_by([r], r.outcome)
      |> select([r], {r.outcome, count(r.id)})
      |> Repo.all()
      |> Map.new()

    %{statuses: statuses, outcomes: outcomes}
  end

  # ── People ──────────────────────────────────────────────────────────────

  @impl true
  def list_people(%{organization_id: organization_id}) do
    ImportedPerson
    |> where([p], p.organization_id == ^organization_id)
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @impl true
  def find_person(%{organization_id: organization_id}, key, value)
      when key in [:email, :phone_key, :user_id] and is_binary(value) do
    ImportedPerson
    |> where([p], p.organization_id == ^organization_id and field(p, ^key) == ^value)
    |> order_by([p], asc: p.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> plain()
  end

  def find_person(_context, _key, _value), do: nil

  @impl true
  def upsert_person(%{organization_id: organization_id}, attrs) do
    case Repo.one(
           from p in ImportedPerson,
             where: p.organization_id == ^organization_id and p.user_id == ^attrs.user_id
         ) do
      nil -> %ImportedPerson{organization_id: organization_id}
      person -> person
    end
    |> ImportedPerson.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, person} -> {:ok, plain(person)}
      error -> error
    end
  end

  @impl true
  def update_person(%{organization_id: organization_id}, id, changes) do
    case Repo.one(
           from p in ImportedPerson, where: p.organization_id == ^organization_id and p.id == ^id
         ) do
      nil ->
        {:error, :not_found}

      person ->
        person
        |> ImportedPerson.changeset(changes)
        |> Repo.update()
        |> case do
          {:ok, person} -> {:ok, plain(person)}
          error -> error
        end
    end
  end

  @impl true
  def people_of_import(%{organization_id: organization_id}, import_id) do
    user_ids =
      from r in ImportRow,
        where:
          r.organization_id == ^organization_id and r.import_id == ^import_id and
            r.status == "applied" and not is_nil(r.user_id),
        select: r.user_id

    ImportedPerson
    |> where([p], p.organization_id == ^organization_id and p.user_id in subquery(user_ids))
    |> order_by([p], asc: p.inserted_at, asc: p.id)
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  defp plain(nil), do: nil
  defp plain(struct), do: struct |> Map.from_struct() |> Map.delete(:__meta__)
end
