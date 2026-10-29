defmodule Palee.Infrastructure.PersonalData.EctoRecordSource do
  @moduledoc """
  Ecto adapter of `Palee.PersonalData.Ports.RecordSource` (ADR-267).

  The person's rows of a catalog entry are found with an Ecto query (the
  entry's subject, plus the business for a `:tenant` entry) that selects
  their `ctid`; the rows themselves are read with Postgres' `row_to_json`,
  so every column comes out with Postgres' own JSON encoding without a
  schema per table. The catalog's secret and other-people columns are then
  dropped (`Catalog.strip/2`). Table and column names only ever come from
  the compile-time catalog and are re-checked as plain identifiers.

  It runs inside the session the facade opened: row-level security still
  decides which rows exist for it.
  """

  @behaviour Palee.PersonalData.Ports.RecordSource

  import Ecto.Query

  alias Palee.PersonalData.Domain.Catalog
  alias Palee.Repo
  alias Palee.TenantData.Domain.RetentionReview

  @impl true
  def organization_ids(user_id) do
    from(m in "organization_memberships",
      where: m.user_id == type(^user_id, :binary_id),
      distinct: true,
      select: type(m.organization_id, :binary_id)
    )
    |> Repo.all()
  end

  @impl true
  def rows(entry, user_id, organization_id) do
    table = identifier!(entry.table)

    query =
      table
      |> from(as: :row)
      |> where(^subject(entry.subject, user_id))
      |> in_business(organization_id)
      |> select([row], field(row, :ctid))

    {ctid_sql, params} = Ecto.Adapters.SQL.to_sql(:all, Repo, query)

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        ~s|SELECT row_to_json(export_row) FROM "#{table}" AS export_row | <>
          ~s|WHERE export_row.ctid IN (#{ctid_sql})|,
        params
      )

    rows
    |> Enum.map(fn [row] -> Catalog.strip(entry, row) end)
    |> Enum.sort_by(&sort_key/1)
  end

  defp in_business(query, nil), do: query

  defp in_business(query, organization_id),
    do: where(query, [row], field(row, :organization_id) == type(^organization_id, :binary_id))

  # A dynamic on the `:row` binding (the entry's own table).
  defp subject({:eq, column}, user_id) do
    column = column!(column)
    dynamic([row: row], field(row, ^column) == type(^user_id, :binary_id))
  end

  defp subject({:in, column, parent, parent_column, parent_subject}, user_id) do
    column = column!(column)
    ids = parent_ids(parent, parent_column, parent_subject, user_id)
    dynamic([row: row], field(row, ^column) in subquery(ids))
  end

  defp subject({:any, subjects}, user_id) do
    Enum.reduce(subjects, dynamic(false), fn one, acc ->
      dynamic(^acc or ^subject(one, user_id))
    end)
  end

  defp parent_ids(parent, parent_column, parent_subject, user_id) do
    parent_column = column!(parent_column)

    parent
    |> identifier!()
    |> from(as: :row)
    |> where(^subject(parent_subject, user_id))
    |> where([row: row], not is_nil(field(row, ^parent_column)))
    |> select([row: row], field(row, ^parent_column))
  end

  defp sort_key(row),
    do: {row["inserted_at"] || row["requested_at"] || "", row["id"] || ""}

  # Safe: names come from the compile-time catalog and are validated.
  defp column!(name), do: name |> identifier!() |> String.to_atom()

  defp identifier!(name) do
    if RetentionReview.valid_identifier?(name),
      do: name,
      else: raise(ArgumentError, "invalid personal data identifier: #{inspect(name)}")
  end
end
